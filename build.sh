#!/bin/bash
# Собирает SleepSwitch.app в ./build. Нужен только установленный Xcode / CLT.
# Версию можно переопределить: VERSION=1.2.3 ./build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/SleepSwitch.app"
BUNDLE_ID="com.ganin.sleepswitch"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>            <string>SleepSwitch</string>
	<key>CFBundleDisplayName</key>     <string>SleepSwitch</string>
	<key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
	<key>CFBundleExecutable</key>      <string>SleepSwitch</string>
	<key>CFBundleIconFile</key>        <string>AppIcon</string>
	<key>CFBundlePackageType</key>     <string>APPL</string>
	<key>CFBundleShortVersionString</key> <string>$VERSION</string>
	<key>CFBundleVersion</key>         <string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>  <string>13.0</string>
	<key>LSUIElement</key>             <true/>
	<key>NSSupportsAutomaticTermination</key> <false/>
</dict>
</plist>
PLIST

echo "Рисую иконку…"
ICONSET="$ROOT/build/AppIcon.iconset"
swift "$ROOT/Tools/make-icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Universal binary: установщик должен ставиться и на Apple Silicon, и на Intel.
SLICES=()
for arch in arm64 x86_64; do
	out="$ROOT/build/SleepSwitch-$arch"
	# Фигурные скобки обязательны: bash 3.2 в неюникодной локали иначе
	# считает следующий за именем многобайтный символ частью имени переменной.
	echo "Компилирую ${arch}…"
	swiftc -O \
		-target "${arch}-apple-macos13.0" \
		-framework AppKit -framework IOKit -framework ServiceManagement \
		-o "$out" \
		"$ROOT/Sources/main.swift"
	SLICES+=("$out")
done

lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/SleepSwitch"
rm -f "${SLICES[@]}"

# Чистим расширенные атрибуты, иначе pkgbuild тащит в пакет мусорные ._-файлы.
xattr -cr "$APP"

# Ad-hoc подпись: без неё macOS не даёт зарегистрировать приложение в автозапуске.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"

echo "Готово: $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/SleepSwitch"))"
