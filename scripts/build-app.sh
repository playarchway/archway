#!/bin/bash
# Builds Archway.app from the SwiftPM product, so macOS picks up the app name, icon, and localizations.
# Usage: scripts/build-app.sh [debug|release]   Output: .build/Archway.app
#
# Addresses and keys come from the environment, or from an ignored .env file in the repository root:
#   ARCHWAY_API_BASE_URL        HTTPS origin of the compatibility service; without it the app has none
#   ARCHWAY_UPDATE_FEED_URL     Sparkle appcast (release builds only)
#   ARCHWAY_SPARKLE_PUBLIC_KEY  Sparkle's public EdDSA key for that appcast (release builds only)
# Release builds need the last two. The release workflow sets all of them from repository variables.
set -euo pipefail

configuration="${1:-debug}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
if [[ -f .env ]]; then
    set -a
    source .env
    set +a
fi
# release-please keeps the version in version.txt.
version="$(tr -d '[:space:]' < version.txt)"
api_base_url="${ARCHWAY_API_BASE_URL:-}"
feed_url="${ARCHWAY_UPDATE_FEED_URL:-}"
sparkle_public_key="${ARCHWAY_SPARKLE_PUBLIC_KEY:-}"
if [[ "$configuration" == release && ( -z "$feed_url" || -z "$sparkle_public_key" ) ]]; then
    echo "Release builds need ARCHWAY_UPDATE_FEED_URL and ARCHWAY_SPARKLE_PUBLIC_KEY" >&2
    exit 1
fi
host_label='[[:alnum:]]([[:alnum:]-]{0,61}[[:alnum:]])?'
if [[ -n "$api_base_url" ]]; then
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
fi

# Swift Build, SwiftPM's default since 6.4, stamps the binary with the deployment target as its SDK version, so
# macOS treats the app as built for macOS 15 and draws it without Liquid Glass. The native build system stamps the
# SDK it links against.
build=(swift build --build-system native --product ArchwayApp -c "$configuration")
"${build[@]}"
bin="$("${build[@]}" --show-bin-path)"

app="$root/.build/Archway.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/ArchwayApp" "$app/Contents/MacOS/Archway"
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Archway"
# Sparkle's XPC services only serve sandboxed apps, and Archway isn't one.
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
rm -rf "$app/Contents/Frameworks/Sparkle.framework/XPCServices" "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
# Sparkle's MIT license asks for its notice in every copy.
mkdir -p "$app/Contents/Resources/Licenses"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$app/Contents/Resources/Licenses/Sparkle-LICENSE.txt"
# Settings → Licenses shows Archway's own license too.
cp LICENSE "$app/Contents/Resources/Licenses/Archway-LICENSE.txt"
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
    <key>CFBundleIdentifier</key><string>app.playarchway.archway</string>
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
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Matthias Schönborn. GPL-3.0.</string>
</dict>
</plist>
PLIST
if [[ -n "$api_base_url" ]]; then
    plutil -insert ArchwayAPIBaseURL -string "$api_base_url" "$app/Contents/Info.plist"
fi
# Sparkle reads updates from the newest release's appcast (see .github/workflows/release.yml) and checks them
# against the public key; release builds only, so local builds never replace themselves.
if [[ "$configuration" == release ]]; then
    plutil -insert SUFeedURL -string "$feed_url" "$app/Contents/Info.plist"
    plutil -insert SUPublicEDKey -string "$sparkle_public_key" "$app/Contents/Info.plist"
fi

# Builds for download are signed with a Developer ID and the hardened runtime, so they can be notarized
# (ARCHWAY_SIGN_IDENTITY, for example "Developer ID Application: …"). Everything else is signed ad hoc.
# Sparkle's helpers are signed first, from the inside out.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
if [[ -n "${ARCHWAY_SIGN_IDENTITY:-}" ]]; then
    sign=(codesign --force --options runtime --timestamp --sign "$ARCHWAY_SIGN_IDENTITY")
else
    sign=(codesign --force --sign -)
fi
for item in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle" "$app"; do
    "${sign[@]}" "$item" >/dev/null
done
echo "$app"
