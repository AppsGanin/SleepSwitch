#!/bin/bash
# Removes SleepSwitch completely: the app, the sudo rule, the preferences and the receipt.
# You do not need this to upgrade — the installer replaces the old copy by itself.
set -euo pipefail

APP="/Applications/SleepSwitch.app"
SUDOERS="/etc/sudoers.d/sleepswitch"
BUNDLE="com.ganin.sleepswitch"

echo "Stopping the app…"
/usr/bin/pkill -x SleepSwitch 2>/dev/null || true
sleep 1

# The sleep ban is a system setting and outlives the app, so it has to go first:
# otherwise the Mac stops sleeping and there is no switch left to turn it off.
# Order matters — the sudo rule is still in place, so this asks for no password.
if /usr/sbin/ioreg -n IOPMrootDomain -r -d 1 | grep -q '"SleepDisabled" = Yes'; then
	echo "Clearing the sleep ban…"
	sudo /usr/bin/pmset -a disablesleep 0
fi

echo "Removing files — an administrator password is required…"
sudo /bin/rm -rf "$APP"
sudo /bin/rm -f "$SUDOERS"
sudo /usr/sbin/pkgutil --forget com.ganin.sleepswitch.app > /dev/null 2>&1 || true
sudo /usr/sbin/pkgutil --forget com.ganin.sleepswitch.sudoers > /dev/null 2>&1 || true

/usr/bin/defaults delete "$BUNDLE" 2>/dev/null || true
/bin/rm -rf "$HOME/Library/Application Support/SleepSwitch"
/bin/rm -rf "$HOME/Library/Saved Application State/$BUNDLE.savedState"

echo
echo "Done, SleepSwitch is gone."
if /usr/sbin/ioreg -n IOPMrootDomain -r -d 1 | grep -q '"SleepDisabled" = Yes'; then
	echo "WARNING: the sleep ban could not be cleared. Run this yourself:"
	echo "  sudo pmset -a disablesleep 0"
else
	echo "The sleep ban is cleared; your Mac sleeps as configured again."
fi
echo "If the app was a login item, the entry disappears from System Settings →"
echo "General → Login Items on its own."
