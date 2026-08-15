#!/bin/bash
# Собирает установщик dist/SleepSwitch-<версия>.pkg.
# Версию можно переопределить: VERSION=1.2.3 ./make-installer.sh
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

echo "Собираю компонент с приложением…"
pkgbuild \
	--root "$STAGE" \
	--install-location /Applications \
	--identifier com.ganin.sleepswitch.app \
	--version "$VERSION" \
	--scripts "$ROOT/packaging/scripts-app" \
	"$PARTS/app.pkg" >/dev/null

echo "Собираю компонент с правилом sudo…"
pkgbuild \
	--nopayload \
	--identifier com.ganin.sleepswitch.sudoers \
	--version "$VERSION" \
	--scripts "$ROOT/packaging/scripts-sudoers" \
	"$PARTS/sudoers.pkg" >/dev/null

sed "s/__VERSION__/$VERSION/g" "$ROOT/packaging/distribution.xml.in" > "$ROOT/build/distribution.xml"

echo "Собираю установщик…"
productbuild \
	--distribution "$ROOT/build/distribution.xml" \
	--package-path "$PARTS" \
	--resources "$ROOT/packaging/resources" \
	"$PKG" >/dev/null

# Staging-копия приложения и компоненты пакета больше не нужны, а лишний бандл
# на диске потом всплывает дубликатом в поиске.
rm -rf "$STAGE" "$PARTS"

echo "Готово: $PKG"
