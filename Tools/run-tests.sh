#!/bin/bash
# Runs the test suite. With --network it also queries the real GitHub API.
# swiftc insists the file carrying top-level code be named main.swift, hence the copy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$ROOT/Tools/check-localization.sh"

cp "$ROOT/Tools/test-updater.swift" "$WORK/main.swift"
swiftc -o "$WORK/tests" "$ROOT/Sources/Updater.swift" "$WORK/main.swift"
"$WORK/tests" "$@"
