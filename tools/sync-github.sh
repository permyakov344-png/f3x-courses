#!/bin/bash
# sync-github.sh -- выгрузить все изменения в GitHub одним движением.
#
# Правило проекта: каждое изменение (код, документация, скриншоты) уходит
# в GitHub сразу, чтобы любую версию можно было вернуть и посмотреть.
#
# Использование:
#   bash tools/sync-github.sh                       # сообщение придумается
#   bash tools/sync-github.sh "что изменилось"      # своё сообщение
#
# Что делает:
#   1. проверяет, что это git-репозиторий и есть remote origin;
#   2. git add -A (включая картинки в docs/screens/);
#   3. коммитит, если есть что коммитить;
#   4. git pull --rebase и git push;
#   5. печатает, что именно ушло.

set -u

cd "$(dirname "$0")/.." || exit 1

# --- проверки ---------------------------------------------------------------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "ОШИБКА: это не git-репозиторий."
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "ОШИБКА: нет remote 'origin'. Сначала:"
  echo "  git remote add origin git@github.com:USER/REPO.git"
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
MSG="${1:-}"

# --- коммит -----------------------------------------------------------------
git add -A

if git diff --cached --quiet; then
  echo "Нечего выгружать: рабочая копия совпадает с последним коммитом."
else
  if [ -z "$MSG" ]; then
    # сообщение по составу изменений
    FILES=$(git diff --cached --name-only)
    COUNT=$(echo "$FILES" | wc -l | tr -d ' ')
    if echo "$FILES" | grep -q "^Apps/"; then
      VER=$(grep -m1 'local appVersion' Apps/f3xc.lua 2>/dev/null | sed 's/.*"\(.*\)".*/\1/')
      MSG="app ${VER:-}: обновление ($COUNT файл(ов))"
    elif echo "$FILES" | grep -q "^docs/screens/"; then
      MSG="docs: скриншоты передатчика и история ($COUNT файл(ов))"
    else
      MSG="docs: обновление документации ($COUNT файл(ов))"
    fi
  fi
  git commit -q -m "$MSG" || { echo "ОШИБКА: коммит не удался"; exit 1; }
  echo "Коммит: $MSG"
fi

# --- синхронизация ----------------------------------------------------------
echo "Синхронизация с origin/$BRANCH ..."
if ! git pull --rebase origin "$BRANCH"; then
  echo
  echo "ОШИБКА: git pull --rebase не прошёл (возможен конфликт)."
  echo "Разбери конфликт вручную, затем повтори: bash tools/sync-github.sh"
  exit 1
fi

if ! git push origin "$BRANCH"; then
  echo "ОШИБКА: git push не прошёл."
  exit 1
fi

# --- отчёт ------------------------------------------------------------------
echo
echo "Выгружено:"
echo "  ветка:  $BRANCH"
echo "  коммит: $(git log -1 --oneline)"
echo "  remote: $(git remote get-url origin)"
echo "  файлы:"
git show --stat --oneline HEAD | tail -n +2 | sed 's/^/    /'
echo
echo "История: git log --oneline    Вернуться: git checkout <коммит>"
