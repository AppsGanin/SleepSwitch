#!/bin/bash
# Сверяет ключи L("...") из исходника со всеми .strings.
# Забытый перевод должен ломать сборку, а не всплывать у пользователя английской строкой.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

grep -ho 'L("[^"]*"' "$ROOT/Sources/"*.swift |
	sed 's/^L("//; s/"$//' | sort -u > "$WORK/used"

status=0
for file in "$ROOT/Resources/"*.lproj/Localizable.strings; do
	lang="$(basename "$(dirname "$file")" .lproj)"
	plutil -lint "$file" > /dev/null

	grep -o '^"[^"]*"' "$file" | tr -d '"' | sort -u > "$WORK/have"

	comm -23 "$WORK/used" "$WORK/have" > "$WORK/missing"
	comm -13 "$WORK/used" "$WORK/have" > "$WORK/extra"

	if [ -s "$WORK/missing" ]; then
		echo "Локализация $lang: нет перевода для ключей:" >&2
		sed 's/^/  /' "$WORK/missing" >&2
		status=1
	fi
	if [ -s "$WORK/extra" ]; then
		echo "Локализация $lang: лишние ключи, в коде не используются:" >&2
		sed 's/^/  /' "$WORK/extra" >&2
		status=1
	fi
done

if [ "$status" -eq 0 ]; then
	echo "Локализация: $(wc -l < "$WORK/used" | tr -d ' ') ключей, все языки на месте."
fi
exit "$status"
