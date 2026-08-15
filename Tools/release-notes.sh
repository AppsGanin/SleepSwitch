#!/bin/bash
# Печатает описание релиза для указанной версии: раздел из CHANGELOG плюс постоянная
# часть на английском и русском. Используется и workflow-ом, и для правки старых релизов,
# чтобы описание везде было одинаковым.
#   ./Tools/release-notes.sh 1.1.1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?нужна версия, например 1.1.1}"

CHANGES="$(awk -v v="## $VERSION" '
	$0 == v { inside = 1; next }
	/^## / && inside { exit }
	inside { print }
' "$ROOT/CHANGELOG.md" | sed '/./,$!d')"

if [ -n "$CHANGES" ]; then
	printf '## What changed\n\n%s\n\n' "$CHANGES"
else
	echo "CHANGELOG не содержит раздела для $VERSION — описание без списка изменений." >&2
fi

# Двуязычным интерфейс стал в 1.1.0; для более старых релизов писать об этом нельзя.
if [ "$(printf '%s\n1.1.0\n' "$VERSION" | sort -V | head -1)" = "1.1.0" ]; then
	EN_LANG=" English and Russian."
	RU_LANG=" Русский и английский."
else
	EN_LANG=" The interface is Russian-only in this version."
	RU_LANG=" Интерфейс в этой версии только на русском."
fi

cat <<NOTES
Menu bar toggle that stops your MacBook from sleeping — lid closed included.

## Install

Download the \`.pkg\` and open it. The installer puts the app in Applications,
launches it, and optionally adds a \`sudo\` rule so toggling never asks for a
password.

> **The app is not signed with an Apple certificate.** macOS blocks the first
> open: right-click the file → **Open** → **Open** again. One-time.

The \`.zip\` is the same app without the installer, if you prefer to place it by hand.

## Usage

Left click the icon to toggle, right click for the menu. Moon — normal mode,
coffee cup — sleep blocked, triangle — partially on (the lid still sleeps).

macOS 13 or newer. Universal — Apple Silicon and Intel.${EN_LANG}

---

## Установка

Скачайте \`.pkg\` и откройте его. Установщик положит приложение в «Программы»,
запустит его и (по желанию) добавит правило \`sudo\`, чтобы режим переключался
без ввода пароля.

> **Приложение не подписано сертификатом Apple.** При первом запуске macOS
> откажется открывать пакет. Правой кнопкой по файлу → **«Открыть»** →
> в диалоге ещё раз **«Открыть»**. Один раз.

Файл \`.zip\` — то же приложение без установщика.

## Управление

Левый клик по иконке — включить или выключить, правый — меню. Луна — обычный
режим, чашка — сон запрещён, треугольник — включён частично (крышка усыпит).

Требуется macOS 13 или новее. Universal — Apple Silicon и Intel.${RU_LANG}
NOTES
