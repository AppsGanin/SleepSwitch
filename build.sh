#!/bin/bash
# Builds SleepSwitch.app into ./build. Xcode or the Command Line Tools is all it needs.
# Override the version with: VERSION=1.2.3 ./build.sh
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
	<key>CFBundleDevelopmentRegion</key> <string>en</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>ru</string>
	</array>
	<key>CFBundleShortVersionString</key> <string>$VERSION</string>
	<key>CFBundleVersion</key>         <string>$VERSION</string>
	<key>LSMinimumSystemVersion</key>  <string>13.0</string>
	<key>LSUIElement</key>             <true/>
	<key>NSSupportsAutomaticTermination</key> <false/>
</dict>
</plist>
PLIST

"$ROOT/Tools/check-localization.sh"
cp -R "$ROOT/Resources/"*.lproj "$APP/Contents/Resources/"

echo "Drawing the icon…"
ICONSET="$ROOT/build/AppIcon.iconset"
swift "$ROOT/Tools/make-icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Universal binary: the installer has to work on Apple Silicon and Intel alike.
SLICES=()
for arch in arm64 x86_64; do
	out="$ROOT/build/SleepSwitch-$arch"
	# The braces are required: in a non-UTF-8 locale bash 3.2 would otherwise read the
	# multibyte character that follows the name as part of the variable name.
	echo "Compiling ${arch}…"
	swiftc -O \
		-target "${arch}-apple-macos13.0" \
		-framework AppKit -framework IOKit -framework ServiceManagement \
		-o "$out" \
		"$ROOT/Sources/"*.swift
	SLICES+=("$out")
done

lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/SleepSwitch"
rm -f "${SLICES[@]}"

# Strip extended attributes, or pkgbuild drags junk ._ entries into the package.
xattr -cr "$APP"

# Ad-hoc signature: without one macOS refuses to register the app as a login item.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"

echo "Done: $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/SleepSwitch"))"
