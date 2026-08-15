#!/bin/bash
# Собирает приложение, кладёт его в /Applications и запускает.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/SleepSwitch.app"

"$ROOT/build.sh"

if pgrep -x SleepSwitch >/dev/null; then
	echo "Останавливаю запущенную копию…"
	pkill -x SleepSwitch || true
	sleep 1
fi

rm -rf "$DEST"
cp -R "$ROOT/build/SleepSwitch.app" "$DEST"
echo "Установлено: $DEST"

open "$DEST"
echo "Иконка появилась в строке меню справа."
