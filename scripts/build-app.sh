#!/bin/bash
# Builds Archway.app from the SwiftPM product, so macOS picks up the app name, icon, and localizations.
# Usage: scripts/build-app.sh [debug|release]   Output: .build/Archway.app
set -euo pipefail

configuration="${1:-debug}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build --product Archway -c "$configuration"
bin="$(swift build --product Archway -c "$configuration" --show-bin-path)"

app="$root/.build/Archway.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Archway" "$app/Contents/MacOS/Archway"
cp -R "$bin/Overcross_Archway.bundle" "$app/Contents/Resources/"
# SwiftUI looks up its strings in the main bundle.
cp -R "$bin/Overcross_Archway.bundle/Contents/Resources/"*.lproj "$app/Contents/Resources/"

iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Sources/Archway/Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Sources/Archway/Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.mschoenb.archway</string>
    <key>CFBundleName</key><string>Archway</string>
    <key>CFBundleDisplayName</key><string>Archway</string>
    <key>CFBundleExecutable</key><string>Archway</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>de</string><string>en</string></array>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app" >/dev/null
echo "$app"
