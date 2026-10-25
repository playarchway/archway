#!/bin/bash
# Builds Archway's Wine tree for x86_64 and installs it into DESTDIR (the files land in DESTDIR/usr/local).
# Usage: scripts/build-wine.sh DESTDIR
# Paths can be overridden with WINE_SOURCE, WINE_BUILD, WINE_TOOLS and BISON_DIR. An unconfigured build
# directory gets a release configuration: no tests, no debug info. Run scripts/fetch-wine-tools.sh first.
set -euo pipefail

destdir="${1:?Usage: scripts/build-wine.sh DESTDIR}"
wine_source="${WINE_SOURCE:-$HOME/dev/archway-wine}"
build="${WINE_BUILD:-$HOME/dev/archway-wine-build/build64}"
tools="${WINE_TOOLS:-$HOME/dev/archway-wine-tools}"
freetype="$tools/freetype-2.15.0/install"
bison="${BISON_DIR:-$tools/host-deps/bison/3.8.2}"
[ -x "$bison/bin/bison" ] || bison="$(brew --prefix bison 2>/dev/null || true)"

[ -f "$freetype/lib/libfreetype.6.dylib" ] || { echo "No x86_64 FreeType in $freetype; run scripts/fetch-wine-tools.sh" >&2; exit 1; }
[ -x "$bison/bin/bison" ] || { echo "No Bison 3; install it with 'brew install bison' or set BISON_DIR" >&2; exit 1; }

export PATH="$bison/bin:$tools/llvm-mingw-20261020-ucrt-macos-universal/bin:$PATH"
export BISON_PKGDATADIR="$bison/share/bison"

echo "Building Wine from $wine_source ($(git -C "$wine_source" log -1 --format='%h %s'))"
if [ ! -f "$build/Makefile" ]; then
    mkdir -p "$build"
    (cd "$build" && "$wine_source/configure" --build=x86_64-apple-darwin --enable-archs=i386,x86_64 \
        --with-mingw=llvm-mingw --disable-tests --with-coreaudio --with-freetype \
        --without-alsa --without-capi --without-cups --without-dbus --without-ffmpeg --without-fontconfig \
        --without-gettext --without-gettextpo --without-gphoto --without-gnutls --without-gssapi \
        --without-gstreamer --without-krb5 --without-netapi --without-opencl --without-oss --without-pcap \
        --without-pcsclite --without-pulse --without-sane --without-sdl --without-udev --without-usb \
        --without-v4l2 --without-va --without-vulkan --without-wayland --without-x \
        CC="/usr/bin/clang -arch x86_64" CFLAGS="-O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0" \
        CROSSCFLAGS="-O2" \
        FREETYPE_CFLAGS="-I$freetype/include/freetype2" FREETYPE_LIBS="-L$freetype/lib -lfreetype" \
        >/dev/null)
fi
make -C "$build" -j"$(sysctl -n hw.ncpu)" >/dev/null
rm -rf "$destdir"
make -C "$build" install DESTDIR="$destdir" >/dev/null
echo "Wine installed: $destdir/usr/local"
