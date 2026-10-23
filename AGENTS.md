# Agent notes

## Wine sessions

Several agents may run Wine on this Mac at the same time. Each session is one wineserver per prefix, and every one of its processes shows up in the Dock as "wine" with the Windows program's icon. Stock Wine (checked on 11.18) cannot show another Dock name: all processes run the same `lib/wine/x86_64-unix/wine` loader, and Wine starts child processes through that fixed path.

Tell sessions apart by prefix instead:

- Run `scripts/wine-sessions.sh` to list every running session with its prefix and Windows programs.
- Work in a prefix of your own under `~/Library/Application Support/Overcross/`. For experiments, clone an existing bottle (`cp -cRp`; APFS makes this nearly free) into a new `<purpose>-probe` directory and add it to the table below. Delete it, and its row, when you are done.
- Stop only your own session: `overcross close-steam` for the default bottle, otherwise `WINEPREFIX=<prefix> <runtime>/bin/wineserver -k`. Never stop Wine globally (`killall wine`, `pkill -f wine`, quitting every "wine" Dock icon); another agent's Steam or test may be running.
- Ask the user before stopping a session in a prefix you do not own.

| Prefix (under `~/Library/Application Support/Overcross/`) | Owner and purpose |
|---|---|
| `bottles/steam-5228920` | Overcross CLI default data directory: the user's Windows Steam, on Whisky's CrossOver-based Wine 11.17 with D3DMetal (`runtime-overlays/winecx-gptk-4.7.3`) for Brick by Brick. Start and stop it only through `overcross`. |
| `graphics-probe` | Earlier DXVK/graphics experiments; not in active use. |
| `runtime-probe/bottle` | Wine 11.18 runtime smoke test; `runtime-probe/extracted` holds the previous runtime (`config.before-d3dmetal.json`). |

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `type(scope): summary` in English, with types such as `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, and `build`. The scope is optional (for example `feat(d3dmetal): …`, `fix(steam): …`). Do not add agent or model attribution trailers.
