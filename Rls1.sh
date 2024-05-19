#!/bin/bash

lock_file="RLS1/rls1.lock" #путь к файлу блокировки

# Проверка существование файла блокировки, Оператор -e проверяет, существует ли файл с указанным путем. Если файл существует, 
# значит скрипт уже запущен, и в этом случае выводится сообщение "Script already work", и скрипт завершает работу.
if [ -e "$lock_file" ]; then
    echo "Script already work"
    exit 1
fi

# Если файл блокировки не существует, то скрипт создает его с помощью команды touch, которая создает пустой файл, если он не существует, 
# или обновляет временные метки доступа к файлу, если он существует.
touch "$lock_file"

# Удаление файла блокировки и завершение работы скрипта.
program_end() {
    rm -f "$lock_file" # флаг -f игнорирует ошибки, если файл уже не существует.
    exit
}
trap program_end EXIT SIGINT # обработчик сигнала, вызывает функцию program_end в случае возникновения сигналов exit или sigint (например для ctrl + c)

directory="/tmp/GenTargets/Targets"
file_path="RLS1/detected_Rls1.txt" # Обнаруженные цели РЛС.
file2_path="RLS1/confrimed_Rls1.txt" # Подтвержденные цели РЛС.
messages_path="messages/information" # Информационные сообщения РЛС.
time_format="%d_%m_%Y_%H-%M-%S.%3N"
source Koordinates.sh  # source запускает скрипт и делает переменные из него доступными для этого скрипта
source Is_in.sh

password="1234"

# Создание сообщения о работоспособности РЛС, шифрование его с использованием заданного пароля
# и запись зашифрованного сообщения в файл с уникальным именем в директорию.
time=$(TZ=Europe/Moscow date +"$time_format") # устанавливаем формат времени
echo "$time,Rls1,i am alive" | openssl aes-256-cbc -pbkdf2 -a -salt -pass pass:$password > "messages/alive/$time.log"

if [ -d "$directory" ]; then # флаг -d означает true, если файл существует и это директория
   echo -n > "$file_path" # Вывод пустой строки без символа перевода строки.
   echo -n > "$file2_path" # Затем этот вывод перенаправляется в файлы $file_path и $file2_path, чтобы очистить их содержимое.
   filenames=() # Массив для хранения имен файлов с данными о целях.
   while true; do
      filenames=($(ls -t "$directory" | head -n 30 2>/dev/null)) # Получение списка файлов с координатами целей. filenames будет содержать имена последних 30 файлов в каталоге
      for name in "${filenames[@]}"; do
         id=$(ls -t "$directory/$name" | tail -c 7 2>/dev/null) # Идентификатор цели из имени файла. (последние 7 символов)
         IFS=, read -r x y < /tmp/GenTargets/Targets/$name 2>/dev/null # Координаты цели из файла с указанным именем. IFS Устанавливает разделитель полей ввода в запятую. -r означает "не интерпретировать обратные слеши"
         x="${x#X}" # Удаление префиксов ${parameter#word}
         y="${y#Y}" # Удаление префиксов ${parameter#word}
         sector=$(target_in_sector $x $y $RLS1_x $RLS1_y $RLS1_RADIUS $RLS1_START_ANGLE $RLS1_END_ANGLE) # Находится ли цель в секторе обзора РЛС.
         if [ "$sector" -eq 1 ]; then # Цель находится в зоне обзора РЛС.
            if ! grep -q "^$id " "$file2_path"; then # Если цель записана в файле confrimed_targets, то мы её игнорируем.
               if grep -q "^$id " "$file_path"; then # Если цель уже встретилась один раз и записана в detected_targets, то считаем её скорость и записываем в confrimed.
                  read -r _ last_x last_y <<< "$(grep "^$id " "$file_path" | tail -n 1)" # считываем последние зафиксированные координаты из файла
                  if [[ $x!=$last_x && $y!=$last_y ]]; then # Проверка движения цели.
                     speed_info=$(calculate_speed $x $y $last_x $last_y) # Считаем скорость между двумя точками (старые и новые координаты)
                     to_spro=$(is_line_through_circle $SPRO_x $SPRO_y $SPRO_RADIUS $x $y $last_x $last_y) # Проверяем, проходит ли траектория цели через зону действия СПРО.
                  fi
                  if [[ -n $speed_info && $speed_info != 0 ]]; then # Есть ли скорость, неравная нулю. (-n - проверка что строка не пустая)
                     echo "$id $speed_info" >> "$file2_path" # Информация о скорости добавляется в файл.
                     type=$(check_speed $speed_info) # Определение типа цели на основе ее скорости.
                     time=$(TZ=Europe/Moscow date +"$time_format") 
                     echo "$time, Confirm target id $id X $x Y $y speed $speed_info type $type" # Вывод информации о подтвержденной цели.
                     echo "$time,Rls1,confirm,$id,$x $y,$speed_info,$type" | openssl aes-256-cbc -pbkdf2 -a -salt -pass pass:$password > "$messages_path/$time.log" # Запись информации о подтвержденной цели в файл журнала сообщений.
                     distance1=$(distance $x $y $SPRO_x $SPRO_y) # Расстояние от текущей позиции цели до центра СПРО.
                     distance2=$(distance $last_x $last_y $SPRO_x $SPRO_y) # Расстояние от предыдущей позиции цели до центра СПРО.
                     if [[ $to_spro == "true" && $type == "ballistic" && $(echo "${distance1} < ${distance2}" | bc -l) ]]; then
                        time=$(TZ=Europe/Moscow date +"$time_format")
                        echo "$time, Target id $id X $x Y $y goes to Spro" # Сообщения о том, что цель направляется к СПРО.
                        echo "$time,Rls1,toSpro,$id,$x $y" | openssl aes-256-cbc -pbkdf2 -a -salt -pass pass:$password > "$messages_path/$time.log" # Запись этого сообщения в файл журнала сообщений.
                     fi
                     speed_info=0
                  fi
               else
                  echo "$id $x $y" >> "$file_path" # Если цель встречается впервые, записываем её id и координаты в файл.
               fi
            fi
         fi
      done
      if [ -f "RLS1/hello.log" ]; then # True if FILE exists and is a regular file.
            decrypted_content=$(openssl aes-256-cbc -pbkdf2 -a -d -salt -pass "pass:$password" -in "RLS1/hello.log")
            if [ "$decrypted_content" = "hello" ]; then
               time=$(TZ=Europe/Moscow date +"$time_format")
               echo "$time,Rls1,i am alive" | openssl aes-256-cbc -pbkdf2 -a -salt -pass pass:$password > "messages/alive/$time.log" # Сообщение о том, что РЛС жива, и запись в файл.
            fi
            rm "RLS1/hello.log"
        fi
   done
else
   echo "Dnf"
fi