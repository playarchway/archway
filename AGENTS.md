# Agent notes

## Wine sessions

Several agents may run Wine on the same Mac at the same time. Each session is one wineserver per prefix, and every one of its processes shows up in the Dock as "wine" with the Windows program's icon. Stock Wine (checked on 11.18) cannot show another Dock name: all processes run the same `lib/wine/x86_64-unix/wine` loader, and Wine starts child processes through that fixed path.

Tell sessions apart by prefix instead:

- Run `scripts/wine-sessions.sh` to list every running session with its prefix and Windows programs.
- Work in a prefix of your own under the current default data directory (`archway locations` prints it). For experiments, clone an existing bottle (`cp -cRp`; APFS makes this nearly free) into a new `<purpose>-probe` directory and add it to the table below. Delete it, and its row, when you are done.
- Stop only your own session: `archway close-steam` for the default bottle, otherwise `WINEPREFIX=<prefix> <runtime>/bin/wineserver -k`. Never stop Wine globally (`killall wine`, `pkill -f wine`, quitting every "wine" Dock icon); another agent's Steam or test may be running.
- Ask the user before stopping a session in a prefix you do not own.

| Prefix (under the current default data directory) | Owner and purpose |
|---|---|
| `bottles/steam-5228920` | The default bottle of the Archway app and CLI: the developer's Windows Steam and games, on Archway's own Wine runtime package (`runtime-overlays/archway-wine-<version>`) with D3DMetal staged. Start and stop it only through `archway` or the app. |

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/): `type(scope): summary` in English, with types such as `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, and `build`. The scope is optional (for example `feat(d3dmetal): …`, `fix(steam): …`). Do not add agent or model attribution trailers.

## App (Archway)

- Build and run the macOS app as a bundle: `scripts/build-app.sh`, then `open .build/Archway.app`. Quit the running instance first (`pkill -x Archway`). The bare SwiftPM binary has no localizations and a different defaults/WebKit storage location.
- UI text is written in English in code. Every new user-facing string needs a German translation in `Sources/Archway/Resources/Localizable.xcstrings`. Strings that are not literals passed to SwiftUI views must use `String(localized:)`.
