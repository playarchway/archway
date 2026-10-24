#!/bin/sh
# Lists running Wine sessions: one wineserver per prefix, with its Windows programs.
# Every Wine process appears as "wine" in the Dock, so use this to tell sessions apart.
set -eu

root="${ARCHWAY_DATA_DIR:-$HOME/Library/Application Support/Archway}"
# Include the former root while a migration is pending, so this audit can see orphan loaders.
legacy_root="$HOME/Library/Application Support/Overcross"
sessions=0

for server in $(pgrep -f '/wineserver$' || true); do
    # wineserver runs in /tmp/.wine-UID/server-<device>-<prefix inode>.
    dir=$(lsof -a -p "$server" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    [ -n "$dir" ] || continue
    inode=$(printf '%d' "0x${dir##*-}")
    prefix=$(find "$root" "$legacy_root" -maxdepth 4 -name system.reg -print 2>/dev/null | while IFS= read -r reg; do
        candidate=$(dirname "$reg")
        [ "$(stat -f %i "$candidate")" = "$inode" ] && printf '%s\n' "$candidate"
    done | head -n 1)
    sessions=$((sessions + 1))
    echo "Prefix: ${prefix:-unknown (outside $root, inode $inode)}"
    echo "  wineserver $server"
    # Wine processes map files from the server directory. Show names without arguments.
    for pid in $(pgrep -f '\.exe' || true); do
        lsof -p "$pid" -Fn 2>/dev/null | grep -qF "$dir/" || continue
        program=$(ps -o comm= -p "$pid" | sed 's!.*/!!')
        printf '  %s %s\n' "$pid" "$program"
    done
done

# BSD ps axeww includes WINEPREFIX for loaders whose wineserver already exited. Inspect it
# in memory and print only the PID, prefix, and program name; never print the environment.
orphan_sessions=$(/usr/bin/python3 - "$root" "$legacy_root" <<'PY'
import re
import subprocess
import sys

roots = tuple(dict.fromkeys(sys.argv[1:]))
lines = subprocess.check_output(["/bin/ps", "axeww", "-o", "pid=,command="], text=True)
for line in lines.splitlines():
    match = re.match(r"\s*(\d+)\s+(.*)", line)
    if not match:
        continue
    pid, command = match.groups()
    if not re.search(r"(?:/| )wine(?:64(?:-preloader)?|-preloader)?(?:\s|$)|(?:/| )winedbg(?:\s|$)|(?:/| )wineserver(?:\s|$)", command):
        continue
    prefix_match = re.search(r"(?:^|\s)WINEPREFIX=(.*?)(?=\s[A-Za-z_][A-Za-z0-9_]*=|$)", command)
    prefix = prefix_match.group(1) if prefix_match else ""
    for root in roots:
        for candidate in (prefix, command):
            start = candidate.find(root)
            if start < 0:
                continue
            before = candidate[start - 1] if start else ""
            end = start + len(root)
            after = candidate[end:end + 1]
            if before not in ("", " ", "=", ":", '"', "'") or after not in ("", "/", "\\", " ", '"', "'"):
                continue
            program = "winedbg" if "winedbg" in command else ("wineserver" if "wineserver" in command else "wine")
            # Build the displayed prefix from a safe path segment alphabet, never from raw environment text.
            suffix = re.match(r"(?:/[A-Za-z0-9._-]+){0,3}", prefix[len(root):]).group(0) if prefix.startswith(root) else ""
            shown = root + suffix if suffix else root + " (process path)"
            print(f"Prefix: {shown}\n  {program} {pid} (server may be absent)")
            break
        else:
            continue
        break
PY
)
[ -z "$orphan_sessions" ] || { printf '%s\n' "$orphan_sessions"; sessions=$((sessions + 1)); }
[ "$sessions" -gt 0 ] || echo "No Wine sessions running."
