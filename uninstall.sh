#!/bin/bash
# Полностью удаляет SleepSwitch: приложение, правило sudo, настройки и запись об установке.
# Для обновления версии этот скрипт не нужен — установщик сам заменяет старую копию.
set -euo pipefail

APP="/Applications/SleepSwitch.app"
SUDOERS="/etc/sudoers.d/sleepswitch"
BUNDLE="com.ganin.sleepswitch"

echo "Останавливаю приложение…"
/usr/bin/pkill -x SleepSwitch 2>/dev/null || true
sleep 1

# Запрет сна — системная настройка, она переживает приложение. Снять его нужно
# до удаления: иначе Mac перестанет засыпать, а переключателя на экране уже не будет.
# Порядок важен — правило sudo пока на месте, поэтому пароль здесь не спросят.
if /usr/sbin/ioreg -n IOPMrootDomain -r -d 1 | grep -q '"SleepDisabled" = Yes'; then
	echo "Снимаю запрет сна…"
	sudo /usr/bin/pmset -a disablesleep 0
fi

echo "Удаляю файлы — потребуется пароль администратора…"
sudo /bin/rm -rf "$APP"
sudo /bin/rm -f "$SUDOERS"
sudo /usr/sbin/pkgutil --forget com.ganin.sleepswitch.app > /dev/null 2>&1 || true
sudo /usr/sbin/pkgutil --forget com.ganin.sleepswitch.sudoers > /dev/null 2>&1 || true

/usr/bin/defaults delete "$BUNDLE" 2>/dev/null || true
/bin/rm -rf "$HOME/Library/Application Support/SleepSwitch"
/bin/rm -rf "$HOME/Library/Saved Application State/$BUNDLE.savedState"

echo
echo "Готово, SleepSwitch удалён."
if /usr/sbin/ioreg -n IOPMrootDomain -r -d 1 | grep -q '"SleepDisabled" = Yes'; then
	echo "ВНИМАНИЕ: запрет сна снять не удалось. Выполните вручную:"
	echo "  sudo pmset -a disablesleep 0"
else
	echo "Запрет сна снят, Mac засыпает как настроено в системе."
fi
echo "Если приложение было в автозапуске, запись пропадёт из «Системные настройки →"
echo "Основные → Объекты входа» сама."
