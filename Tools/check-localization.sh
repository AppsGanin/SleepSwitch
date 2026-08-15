#!/bin/bash
# Diffs the L("…") keys used in the sources against every Localizable.strings.
# A forgotten translation should break the build, not surface as stray English later.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

grep -ho 'L("[^"]*"' "$ROOT/Sources/"*.swift |
	sed 's/^L("//; s/"$//' | sort -u > "$WORK/used"

status=0
for file in "$ROOT/Resources/"*.lproj/Localizable.strings; do
	language="$(basename "$(dirname "$file")" .lproj)"
	plutil -lint "$file" > /dev/null

	grep -o '^"[^"]*"' "$file" | tr -d '"' | sort -u > "$WORK/have"

	comm -23 "$WORK/used" "$WORK/have" > "$WORK/missing"
	comm -13 "$WORK/used" "$WORK/have" > "$WORK/unused"

	if [ -s "$WORK/missing" ]; then
		echo "Localization $language: no translation for these keys:" >&2
		sed 's/^/  /' "$WORK/missing" >&2
		status=1
	fi
	if [ -s "$WORK/unused" ]; then
		echo "Localization $language: keys nothing in the sources asks for:" >&2
		sed 's/^/  /' "$WORK/unused" >&2
		status=1
	fi
done

if [ "$status" -eq 0 ]; then
	echo "Localization: $(wc -l < "$WORK/used" | tr -d ' ') keys, every language complete."
fi
exit "$status"
