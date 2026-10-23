#!/bin/sh
# Builds the Windows steamwebhelper shim bundled as an OvercrossCore resource.
# Requires Zig (https://ziglang.org); set ZIG to its path if it is not on PATH.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="$here/../../Sources/OvercrossCore/Resources/steamwebhelper-shim.exe"
mkdir -p "$(dirname "$out")"
"${ZIG:-zig}" cc -target x86_64-windows-gnu -municode -Os -s \
    -Wl,--subsystem,windows -o "$out" "$here/steamwebhelper_shim.c" -luser32
shasum -a 256 "$out"
