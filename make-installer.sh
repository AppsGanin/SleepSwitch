#!/bin/bash
# Builds the installer at dist/SleepSwitch-<version>.pkg.
# Override the version with: VERSION=1.2.3 ./make-installer.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
export VERSION

STAGE="$ROOT/build/pkgroot"
PARTS="$ROOT/build/pkgs"
DIST="$ROOT/dist"
PKG="$DIST/SleepSwitch-$VERSION.pkg"

"$ROOT/build.sh"

rm -rf "$STAGE" "$PARTS"
mkdir -p "$STAGE" "$PARTS" "$DIST"
cp -R "$ROOT/build/SleepSwitch.app" "$STAGE/SleepSwitch.app"

echo "Building the app component…"
pkgbuild \
	--root "$STAGE" \
	--install-location /Applications \
	--identifier com.ganin.sleepswitch.app \
	--version "$VERSION" \
	--scripts "$ROOT/packaging/scripts-app" \
	"$PARTS/app.pkg" >/dev/null

echo "Building the sudo rule component…"
pkgbuild \
	--nopayload \
	--identifier com.ganin.sleepswitch.sudoers \
	--version "$VERSION" \
	--scripts "$ROOT/packaging/scripts-sudoers" \
	"$PARTS/sudoers.pkg" >/dev/null

sed "s/__VERSION__/$VERSION/g" "$ROOT/packaging/distribution.xml.in" > "$ROOT/build/distribution.xml"

echo "Building the installer…"
productbuild \
	--distribution "$ROOT/build/distribution.xml" \
	--package-path "$PARTS" \
	--resources "$ROOT/packaging/resources" \
	"$PKG" >/dev/null

# The staging copy and the component packages are no longer needed, and a spare bundle
# lying around later shows up as a duplicate in Spotlight.
rm -rf "$STAGE" "$PARTS"

echo "Done: $PKG"
