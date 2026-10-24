#!/bin/bash
# Builds Archway's alpha runtime ("Archway · Wine 11.20") from our Wine tree and installs it into the
# alpha data directory: Wine, FreeType next to it, and D3DMetal staged on top.
# Usage: scripts/build-alpha-runtime.sh
# Paths can be overridden with WINE_SOURCE, WINE_BUILD and WINE_TOOLS. The build directory must already
# be configured (see AGENTS.md).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# Phase 3 will rename local Wine trees; use existing legacy folders until then.
prefer_existing_dir() {
    if [ -d "$1" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi
}
wine_source="${WINE_SOURCE:-$(prefer_existing_dir "$HOME/dev/archway-wine" "$HOME/dev/overcross-wine")}"
build="${WINE_BUILD:-$(prefer_existing_dir "$HOME/dev/archway-wine-build/build64" "$HOME/dev/overcross-wine-build/build64")}"
tools="${WINE_TOOLS:-$(prefer_existing_dir "$HOME/dev/archway-wine-tools" "$HOME/dev/overcross-wine-tools")}"
# Phase 2 will move the existing alpha bottle with the rest of the app data.
data="$HOME/Library/Application Support/Overcross/archway-alpha"
runtime="$data/runtime-overlays/upstream-11.20/Wine"
install="$(dirname "$build")/install-alpha"
freetype="$tools/freetype-2.15.0/install/lib/libfreetype.6.dylib"

[ -f "$build/Makefile" ] || { echo "No configured Wine build in $build" >&2; exit 1; }
[ -f "$freetype" ] || { echo "No x86_64 FreeType at $freetype" >&2; exit 1; }
if [[ "$("$root/scripts/wine-sessions.sh")" == *"$data/"* ]]; then
    echo "Wine is running in the alpha bottle. Stop it first:" >&2
    echo "  WINEPREFIX=\"$data/bottles/steam-5228920\" \"$runtime/bin/wineserver\" -k" >&2
    exit 1
fi

echo "Building Wine from $wine_source ($(git -C "$wine_source" log -1 --format='%h %s'))"
export PATH="$tools/llvm-mingw-20261020-ucrt-macos-universal/bin:$PATH"
make -C "$build" -j"$(sysctl -n hw.ncpu)" >/dev/null
rm -rf "$install"
make -C "$build" install DESTDIR="$install" >/dev/null

swift build --package-path "$root" --product archway >/dev/null
archway="$(swift build --package-path "$root" --product archway --show-bin-path)/archway"
redist="$(/usr/bin/python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["d3dMetalDirectory"])' "$data/config.json")"

# Put Wine's own Direct3D DLLs back so the update starts from a clean tree.
if [ -d "$runtime/.overcross-d3dmetal-backup" ]; then
    "$archway" --data-dir "$data" restore-d3dmetal --redist-lib "$redist" --runtime-root "$runtime"
fi

# Copy only changed files: an unchanged wine.inf keeps its date, so the bottle skips a prefix update.
mkdir -p "$runtime"
rsync -rlc "$install/usr/local/" "$runtime/"
# Wine loads FreeType by name; the bottle's config points DYLD_LIBRARY_PATH at the runtime's lib folder.
rsync -c "$freetype" "$runtime/lib/"

# D3DMetal only stages into runtimes that declare GPTK support, as Whisky's runtimes do.
plist="$(dirname "$runtime")/WhiskyWineVersion.plist"
[ -f "$plist" ] || cat > "$plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>gptkCapable</key><true/></dict></plist>
PLIST
"$archway" --data-dir "$data" stage-d3dmetal --redist-lib "$redist" --runtime-root "$runtime"
"$archway" --data-dir "$data" configure --wine "$runtime/bin/wine" --wineserver "$runtime/bin/wineserver" \
    --library-dir "$runtime/lib" --backend d3dmetal --d3dmetal-dir "$redist" >/dev/null
echo "Alpha runtime ready: $runtime"
