#!/bin/bash
# Runs the test suite. With --network it also queries the real GitHub API.
#
# There is no Xcode test target on purpose: the suite is a plain executable built from the
# same sources with swiftc, so the whole project still needs nothing but the toolchain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$ROOT/Tools/check-localization.sh"

# Only the AppKit-free half of the app takes part: everything the tests actually drive.
swiftc -o "$WORK/tests" \
	-framework IOKit \
	"$ROOT/Sources/Localization.swift" \
	"$ROOT/Sources/PowerAssertions.swift" \
	"$ROOT/Sources/SystemSleepBan.swift" \
	"$ROOT/Sources/SleepMode.swift" \
	"$ROOT/Sources/Updater.swift" \
	"$ROOT/Tools/tests/"*.swift

"$WORK/tests" "$@"
