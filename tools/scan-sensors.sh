#!/bin/bash
# Ищет подключённый передатчик JETI (или SD-карту) и печатает привязку сенсоров
# из файлов моделей. Запуск: bash tools/scan-sensors.sh
set -u

found=0
for vol in /Volumes/*; do
  name=$(basename "$vol")
  [ "$name" = "Macintosh HD" ] && continue

  # передатчик узнаём по каталогу Model (у DS-24 он в единственном числе) или Apps
  if [ ! -d "$vol/Model" ] && [ ! -d "$vol/Models" ] && [ ! -d "$vol/Apps" ] && [ ! -d "$vol/Config" ]; then
    continue
  fi

  found=1
  echo "==================== Том: $vol"
  echo "-- верхний уровень:"
  ls -1 "$vol" 2>/dev/null | head -40

  for md in "$vol/Model" "$vol/Models"; do
    if [ -d "$md" ]; then
      echo
      echo "-- модели в $(basename "$md")/:"
      ls -1 "$md" 2>/dev/null | head -60
    fi
  done

  if [ -d "$vol/Apps" ]; then
    echo
    echo "-- Apps:"
    ls -1 "$vol/Apps" 2>/dev/null | head -40
  fi

  # ищем модели по обоим вариантам имени каталога
  for md in "$vol/Model" "$vol/Models"; do
    [ -d "$md" ] || continue
    echo
    echo "-- имена датчиков из $(basename "$md")/*.jsn:"
    find "$md" -maxdepth 2 -type f -name '*.jsn' 2>/dev/null | while read -r f; do
      hits=$(strings -a "$f" 2>/dev/null \
        | grep -Eio '"(MGPS|MSPEED|MGPSLOG[0-9]*|GPSLog[0-9]*|GPS|MTEK|MUI[0-9]*|MBar|MVolt|MCurr|MCAP|MRPM|MTEMP|MESC|RCGPS[A-Za-z0-9\-]*)[^"]*"' \
        | sort -u)
      if [ -n "$hits" ]; then
        echo "   [$(basename "$f")]"
        echo "$hits" | sed 's/^/     /'
      fi
    done

    echo
    echo "-- блоки телеметрии в $(basename "$md")/*.jsn:"
    find "$md" -maxdepth 2 -type f -name '*.jsn' 2>/dev/null | while read -r f; do
      block=$(strings -a "$f" 2>/dev/null | grep -Ei 'ensor|Telem|Latitude|Longitude' | head -60)
      if [ -n "$block" ]; then
        echo "   [$(basename "$f")]"
        echo "$block" | sed 's/^/     /'
      fi
    done
  done

  echo
done

if [ "$found" = 0 ]; then
  echo "Передатчик не найден."
  echo "Включи DS-24 -> Menu -> USB -> 'USB Mass Storage' (или просто подключи кабелем)."
  echo "Диск должен появиться в /Volumes, обычно как 'JETI' или 'DS-24'."
fi
exit 0
