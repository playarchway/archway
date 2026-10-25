#!/bin/bash
# Packs a Wine install, FreeType, Wine Mono, and D3DMetal into a runtime archive that Archway can download.
# Usage: scripts/package-runtime.sh WINE_INSTALL GPTK OUTPUT_DIR VERSION
#   WINE_INSTALL  Wine's install prefix (DESTDIR/usr/local from scripts/build-wine.sh)
#   GPTK          Apple's "Evaluation environment for Windows games" .dmg, or its mounted volume
#   OUTPUT_DIR    receives archway-wine-VERSION.tar.xz and its .sha256
# WINE_SOURCE (the Wine tree, for the source notice) and WINE_TOOLS (FreeType, Mono) can be overridden.
#
# The archive holds Wine/ and WhiskyWineVersion.plist; unpack it as DATA/runtime-overlays/NAME/.
# GPTK's license allows non-commercial redistribution of D3DMetal with its notices; its License.rtf
# ships in Wine/lib/external. Wine is LGPL: the archive names the exact source commit.
set -euo pipefail

wine_install="${1:?Usage: scripts/package-runtime.sh WINE_INSTALL GPTK OUTPUT_DIR VERSION}"
gptk="${2:?}"
output="${3:?}"
version="${4:?}"
root="$(cd "$(dirname "$0")/.." && pwd)"
wine_source="${WINE_SOURCE:-$HOME/dev/archway-wine}"
tools="${WINE_TOOLS:-$HOME/dev/archway-wine-tools}"
freetype="$tools/freetype-2.15.0/install/lib/libfreetype.6.dylib"
mono="$tools/wine-mono-11.3.0"

[ -x "$wine_install/bin/wine" ] || { echo "No Wine install in $wine_install" >&2; exit 1; }
[ -f "$freetype" ] && [ -d "$mono" ] || { echo "No FreeType or Wine Mono in $tools; run scripts/fetch-wine-tools.sh" >&2; exit 1; }

# Archway checks that staging happens inside its data directory, so resolve /var to /private/var.
staging="$(cd "$(mktemp -d)" && pwd -P)"
mounted=""
cleanup() {
    [ -z "$mounted" ] || hdiutil detach -quiet "$mounted" || true
    rm -rf "$staging"
}
trap cleanup EXIT

if [ -f "$gptk" ]; then
    mounted="$staging/gptk"
    mkdir "$mounted"
    hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mounted" "$gptk"
    gptk="$mounted"
fi
[ -d "$gptk/redist/lib/external/D3DMetal.framework" ] && [ -f "$gptk/License.rtf" ] ||
    { echo "Not a GPTK evaluation environment: $gptk" >&2; exit 1; }

data="$staging/data"
package="$data/runtime-overlays/archway-wine"
runtime="$package/Wine"
mkdir -p "$runtime"
# Headers are only needed to build against Wine.
rsync -a --exclude /include --exclude /share/man --exclude /share/applications "$wine_install/" "$runtime/"
# Wine loads FreeType by name; Archway points DYLD_LIBRARY_PATH at Wine/lib.
cp "$freetype" "$runtime/lib/"
install_name_tool -id @rpath/libfreetype.6.dylib "$runtime/lib/libfreetype.6.dylib" 2>/dev/null
codesign --force --sign - "$runtime/lib/libfreetype.6.dylib" 2>/dev/null
# A shared Mono in Wine's data directory spares each new bottle the Mono download dialog.
mkdir -p "$runtime/share/wine/mono"
cp -R "$mono" "$runtime/share/wine/mono/"

cat > "$package/WhiskyWineVersion.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>gptkCapable</key><true/></dict></plist>
PLIST
swift build --package-path "$root" --product archway >/dev/null
archway="$(swift build --package-path "$root" --product archway --show-bin-path)/archway"
"$archway" --data-dir "$data" stage-d3dmetal --redist-lib "$gptk/redist/lib" --runtime-root "$runtime" >/dev/null
cp "$gptk/License.rtf" "$runtime/lib/external/GPTK-License.rtf"
cp "$gptk/Acknowledgements.rtf" "$runtime/lib/external/GPTK-Acknowledgements.rtf" 2>/dev/null || true

notices="$runtime/share/doc/archway-wine"
mkdir -p "$notices"
cp "$wine_source/COPYING.LIB" "$wine_source/LICENSE" "$wine_source/AUTHORS" "$notices/"
cp "$(dirname "$freetype")/../share/doc/freetype2/LICENSE.TXT" "$notices/FreeType-LICENSE.TXT" 2>/dev/null ||
    cp "$(dirname "$freetype")/../../LICENSE.TXT" "$notices/FreeType-LICENSE.TXT"
cat > "$notices/SOURCE" <<EOF
Archway Wine $version
Wine source: $(git -C "$wine_source" remote get-url origin | sed 's|^git@github.com:|https://github.com/|') at $(git -C "$wine_source" rev-parse HEAD)
FreeType: 2.15.0 (https://freetype.org)
Wine Mono: 11.3.0 (https://github.com/wine-mono/wine-mono, MIT and LGPL components)
D3DMetal: Apple Game Porting Toolkit evaluation environment, unmodified (see lib/external/GPTK-License.rtf)
EOF

mkdir -p "$output"
archive="$output/archway-wine-$version.tar.xz"
tar -C "$package" -cf - . | xz -T0 -6 > "$archive"
(cd "$output" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "$archive ($(du -h "$archive" | cut -f1))"
