#!/bin/bash
# Builds the app, drops it into /Applications and launches it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="/Applications/SleepSwitch.app"

"$ROOT/build.sh"

if pgrep -x SleepSwitch >/dev/null; then
	echo "Stopping the running copy…"
	pkill -x SleepSwitch || true
	sleep 1
fi

# After an install from the .pkg the bundle belongs to root and a plain rm cannot
# remove it: the inner directories are root-owned and not writable. Hence sudo.
SUDO=""
if [ -e "$DEST" ] && [ ! -w "$DEST/Contents" ]; then
	echo "/Applications holds a copy installed from the package (owned by root)."
	echo "Replacing it needs an administrator password."
	SUDO="sudo"
fi

$SUDO rm -rf "$DEST"
$SUDO cp -R "$ROOT/build/SleepSwitch.app" "$DEST"
echo "Installed: $DEST"

if [ -n "$SUDO" ]; then
	# After sudo cp the bundle would stay root-only; hand it back so the next
	# install needs no password.
	sudo chown -R "$(id -u):$(id -g)" "$DEST"
fi

open "$DEST"
echo "The icon is now on the right-hand side of the menu bar."
