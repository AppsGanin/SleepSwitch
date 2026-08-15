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

# Если раньше ставили из .pkg, бандл принадлежит root, и обычным rm его не снести:
# внутренние папки принадлежат root и закрыты на запись. Тогда идём через sudo.
SUDO=""
if [ -e "$DEST" ] && [ ! -w "$DEST/Contents" ]; then
	echo "В /Applications лежит копия, установленная пакетом (владелец root)."
	echo "Для замены нужен пароль администратора."
	SUDO="sudo"
fi

$SUDO rm -rf "$DEST"
$SUDO cp -R "$ROOT/build/SleepSwitch.app" "$DEST"
echo "Установлено: $DEST"

if [ -n "$SUDO" ]; then
	# После sudo cp бандл остался бы root-only; возвращаем владельца, чтобы
	# следующая установка обошлась без пароля.
	sudo chown -R "$(id -u):$(id -g)" "$DEST"
fi

open "$DEST"
echo "Иконка появилась в строке меню справа."
