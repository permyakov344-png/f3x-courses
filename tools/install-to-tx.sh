#!/bin/bash
# Копирует приложение на подключённый передатчик JETI и печатает список сенсоров.
# Запуск:  bash tools/install-to-tx.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TX=""

for vol in /Volumes/*; do
  name=$(basename "$vol")
  [ "$name" = "Macintosh HD" ] && continue
  if [ -d "$vol/Model" ] || [ -d "$vol/Models" ] || [ -d "$vol/Apps" ]; then
    TX="$vol"; break
  fi
done

if [ -z "$TX" ]; then
  echo "Передатчик не найден в /Volumes."
  echo "Подключи DS-24: Menu -> USB -> 'USB Mass Storage'."
  exit 1
fi

echo "Передатчик: $TX"
mkdir -p "$TX/Apps/f3xc" 2>/dev/null || { echo "Нет прав на запись в $TX/Apps"; exit 1; }

cp "$REPO/Apps/f3xc.lua" "$TX/Apps/f3xc.lua" \
  && echo "  скопировано: Apps/f3xc.lua" \
  || echo "  ОШИБКА: Apps/f3xc.lua"
cp "$REPO/tools/sensors_dump.lua" "$TX/Apps/sensors_dump.lua" \
  && echo "  скопировано: Apps/sensors_dump.lua (диагностика)" \
  || echo "  ОШИБКА: Apps/sensors_dump.lua"

sync
echo
echo "Готово. Выключи/включи передатчик -> Menu -> Applications."
echo "Сначала запусти 'F3X Sensors Dump' — он положит Apps/f3xc/sensors.txt."
echo
echo "--- сенсоры, уже прописанные в моделях:"
for md in "$TX/Model" "$TX/Models"; do
  [ -d "$md" ] || continue
  find "$md" -maxdepth 2 -type f -name '*.jsn' 2>/dev/null | while read -r f; do
    hits=$(strings -a "$f" 2>/dev/null | grep -Ei 'MGPS|GPSLog|RCGPS|MSPEED|MTEK|MUI[0-9]|MBar' | sort -u | head -20)
    [ -n "$hits" ] && { echo "[$(basename "$f")]"; echo "$hits" | sed 's/^/   /'; }
  done
done
