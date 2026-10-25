#!/bin/bash
# Downloads the pinned toolchain for building Archway's Wine, builds an x86_64 FreeType with it, and
# fetches the Wine Mono that the runtime package ships.
# Usage: scripts/fetch-wine-tools.sh [TOOLS_DIR]   (default: $WINE_TOOLS or ~/dev/archway-wine-tools)
# Bison 3 comes from Homebrew (`brew install bison`) or $BISON_DIR; macOS only ships Bison 2.3.
set -euo pipefail

tools="${1:-${WINE_TOOLS:-$HOME/dev/archway-wine-tools}}"
llvm_mingw="llvm-mingw-20261020-ucrt-macos-universal"
llvm_mingw_url="https://github.com/mstorsjo/llvm-mingw/releases/download/20261020/$llvm_mingw.tar.xz"
llvm_mingw_sha256="e9c13e4ede38e715003ffc674d4d00a1088df8235439d1f0c16188ff0704c17e"
freetype="freetype-2.15.0"
freetype_url="https://downloads.sourceforge.net/project/freetype/freetype2/2.15.0/$freetype.tar.xz"
freetype_sha256="93cd47eb719c325107f2d3cf087d06299e944c3b48a40b55537302304dea1dd5"
# Wine 11.20 expects this Mono (MONO_VERSION in dlls/appwiz.cpl/addons.c).
mono="wine-mono-11.3.0"
mono_url="https://github.com/wine-mono/wine-mono/releases/download/$mono/$mono-x86.tar.xz"
mono_sha256="54a1b0111c3fe4b785eae688af94d27e64995707ad648b6fee8000381b80d298"

mkdir -p "$tools"
cd "$tools"

fetch() { # url sha256 file
    if [ ! -f "$3" ]; then
        curl -fsSL --retry 3 -o "$3.partial" "$1"
        mv "$3.partial" "$3"
    fi
    echo "$2  $3" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch: $tools/$3" >&2; exit 1; }
}

fetch "$llvm_mingw_url" "$llvm_mingw_sha256" "$llvm_mingw.tar.xz"
[ -d "$llvm_mingw" ] || tar -xf "$llvm_mingw.tar.xz"

fetch "$freetype_url" "$freetype_sha256" "$freetype.tar.xz"
if [ ! -f "$freetype/install/lib/libfreetype.6.dylib" ]; then
    [ -d "$freetype" ] || tar -xf "$freetype.tar.xz"
    # Wine only needs FreeType itself; without optional codecs it depends on nothing but libSystem.
    (cd "$freetype" &&
        CC="clang -arch x86_64" ./configure --host=x86_64-apple-darwin --prefix="$tools/$freetype/install" \
            --enable-shared --disable-static --with-zlib=no --with-bzip2=no --with-png=no \
            --with-harfbuzz=no --with-brotli=no >/dev/null &&
        make -j"$(sysctl -n hw.ncpu)" >/dev/null &&
        make install >/dev/null)
fi

fetch "$mono_url" "$mono_sha256" "$mono-x86.tar.xz"
[ -d "$mono" ] || tar -xf "$mono-x86.tar.xz"
echo "Wine tools ready: $tools"
