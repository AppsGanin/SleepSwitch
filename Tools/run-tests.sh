#!/bin/bash
# Прогоняет тесты. С --network дополнительно ходит на GitHub за настоящим релизом.
# swiftc требует, чтобы файл с кодом верхнего уровня назывался main.swift, — отсюда копия.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$ROOT/Tools/check-localization.sh"

cp "$ROOT/Tools/test-updater.swift" "$WORK/main.swift"
swiftc -o "$WORK/tests" "$ROOT/Sources/Updater.swift" "$WORK/main.swift"
"$WORK/tests" "$@"
