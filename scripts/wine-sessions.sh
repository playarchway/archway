#!/bin/sh
# Lists running Wine sessions: one wineserver per prefix, with its Windows programs.
# Every Wine process appears as "wine" in the Dock, so use this to tell sessions apart.
set -eu

# Phase 2 will migrate the existing default data directory.
root="${ARCHWAY_DATA_DIR:-$HOME/Library/Application Support/Overcross}"
sessions=0

for server in $(pgrep -f '/wineserver$' || true); do
    # wineserver runs in /tmp/.wine-UID/server-<device>-<prefix inode>.
    dir=$(lsof -a -p "$server" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    [ -n "$dir" ] || continue
    inode=$(printf '%d' "0x${dir##*-}")
    prefix=$(find "$root" -maxdepth 4 -name system.reg -print 2>/dev/null | while IFS= read -r reg; do
        candidate=$(dirname "$reg")
        [ "$(stat -f %i "$candidate")" = "$inode" ] && printf '%s\n' "$candidate"
    done | head -n 1)
    sessions=$((sessions + 1))
    echo "Prefix: ${prefix:-unknown (outside $root, inode $inode)}"
    echo "  wineserver $server"
    # Wine processes show their Windows command line and map files from the server directory.
    for pid in $(pgrep -f '\.exe' || true); do
        lsof -p "$pid" -Fn 2>/dev/null | grep -qF "$dir/" || continue
        printf '  %s\n' "$(ps -o pid=,args= -p "$pid" | cut -c1-100)"
    done
done

[ "$sessions" -gt 0 ] || echo "No Wine sessions running."
