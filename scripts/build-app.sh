#!/bin/bash
# Builds Archway.app from the SwiftPM product, so macOS picks up the app name, icon, and localizations.
# Usage: scripts/build-app.sh [debug|release]   Output: .build/Archway.app
set -euo pipefail

configuration="${1:-debug}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
# release-please keeps the version in version.txt.
version="$(tr -d '[:space:]' < version.txt)"
api_base_url="${ARCHWAY_API_BASE_URL:-https://archway-compatibility.vercel.app}"
host_label='[[:alnum:]]([[:alnum:]-]{0,61}[[:alnum:]])?'
if [[ ! "$api_base_url" =~ ^https://$host_label(\.$host_label)*(:[0-9]{1,5})?/?$ ]]; then
    echo "ARCHWAY_API_BASE_URL must be an HTTPS origin without a path, credentials, query, or fragment" >&2
    exit 1
fi
authority="${api_base_url#https://}"
if [[ "$authority" == *:* ]]; then
    port="${authority##*:}"
    port="${port%/}"
    if (( 10#$port < 1 || 10#$port > 65535 )); then
        echo "ARCHWAY_API_BASE_URL port must be between 1 and 65535" >&2
        exit 1
    fi
fi

swift build --product ArchwayApp -c "$configuration"
bin="$(swift build --product ArchwayApp -c "$configuration" --show-bin-path)"

app="$root/.build/Archway.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/ArchwayApp" "$app/Contents/MacOS/Archway"
cp -R "$bin"/Archway_*.bundle "$app/Contents/Resources/"
# SwiftUI looks up its strings in the main bundle. Not every SwiftPM toolchain compiles string catalogs,
# so compile it here.
xcrun xcstringstool compile Sources/Archway/Resources/Localizable.xcstrings --output-directory "$app/Contents/Resources"

iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Sources/Archway/Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Sources/Archway/Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.mschoenb.archway</string>
    <key>CFBundleName</key><string>Archway</string>
    <key>CFBundleDisplayName</key><string>Archway</string>
    <key>CFBundleExecutable</key><string>Archway</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>de</string><string>en</string></array>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
plutil -insert ArchwayAPIBaseURL -string "$api_base_url" "$app/Contents/Info.plist"

codesign --force --sign - "$app" >/dev/null
echo "$app"
