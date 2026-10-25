# Archway technical proof of concept

Archway is a Swift command-line core for testing **Brick by Brick: Tidy Up the Small Town!** (Steam app `5228920`) in a dedicated Wine bottle on macOS. The app does not bundle Wine, Steam, or a game; the Wine runtime is a separate download (see [Runtime package](#runtime-package)). Its library target is intended for a later native SwiftUI app.

**Verified setup (2026-10-23, macOS 27.0.1, Apple M5 Pro):** Windows Steam and Brick by Brick run in the owned bottle on Whisky's CrossOver-based Wine 11.17 runtime with Apple's D3DMetal (GPTK 4.0 beta 3) for the game and the steamwebhelper shim for Steam's UI. Install, play, save, quit, relaunch, and save reload passed manually. Unity reports `Direct3D 11.0 [level 11.1]` on `AMD Compatibility Mode`, D3DMetal's adapter.

## Prerequisites and commands

Install or select a freely usable macOS Wine runtime separately, and download the official **Windows** Steam installer yourself. Use absolute local paths. Archway never requests your Steam credentials; sign in through the Windows Steam window.

```sh
# With the installed macOS Command Line Tools (Swift 6.4):
swift test -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
swift run archway help
swift run archway doctor
swift run archway configure --wine '/absolute/path/to/wine' --wineserver '/absolute/path/to/wineserver'
swift run archway init-bottle
swift run archway install-steam --installer '/absolute/path/to/SteamSetup.exe'
swift run archway doctor
swift run archway open-steam
swift run archway open-steam --without-webhelper-shim
swift run archway close-steam
swift run archway open-steam --disable-cef-gpu
swift run archway open-steam --wine-renderer gl
swift run archway install-game
swift run archway launch-game
swift run archway locations
```

`--wineserver` is optional for normal launches but required for `close-steam`. The default game ID is `5228920`; `install-game` and `launch-game` also accept `--app-id` with a positive 32-bit Steam ID. Add `--data-dir '/absolute/path'` to any command for an isolated local probe. The default data directory remains at its existing application support location until data migration; `archway locations` prints its path. It contains `config.json`, `bottles/steam-5228920`, and `logs/`. Archway uses only this bottle as `WINEPREFIX`. It does not modify the native macOS Steam installation.

Some local Wine builds require a separate directory of support libraries. If your selected runtime needs one, add `--library-dir '/absolute/path/to/support-libs'` to `configure`. Archway validates and saves one existing directory, then sets `DYLD_LIBRARY_PATH` to that directory for its Wine and wineserver requests. Inherited DYLD variables remain excluded. This is an optional local runtime setting, not a validated runtime distribution.

For a separate renderer experiment, `configure` also accepts `--dxvk-config '/absolute/path/to/dxvk.conf' --vulkan-icd '/absolute/path/to/icd.json'`. Supply both existing readable files or neither. Archway saves their canonical paths and sets `DXVK_CONFIG_FILE` and `VK_ICD_FILENAMES` only from that configuration for its Wine requests; inherited DXVK and Vulkan variables remain excluded. This is an opt-in probe, not a validated game profile. Use a separate `--data-dir` to keep the current bottle and configuration untouched.

As an alternative to the interactive installer command above, add `--silent` to pass only NSIS `/S` to the locally supplied Windows installer. The installer chooses its normal location. Both modes dispatch a request; check `doctor` for the Steam executable afterward. Steam account login still happens in the Windows Steam GUI.

### Runtime package

The Runtime workflow (`.github/workflows/runtime.yml`, started by hand on a Blacksmith macOS runner) builds the runtime that Archway is meant to download: our Wine tree from `Leafline-Labs/archway-wine`, FreeType 2.15.0, Wine Mono 11.3.0 (shared, so new bottles skip the Mono download dialog), and D3DMetal staged on top. It publishes `archway-wine-VERSION.tar.xz` with a SHA-256 file as a `runtime-VERSION` prerelease. The archive holds `Wine/` and `WhiskyWineVersion.plist`; unpack it to `DATA/runtime-overlays/NAME/` and configure Archway with `--library-dir` and `--d3dmetal-dir` both set to `DATA/runtime-overlays/NAME/Wine/lib`. Wine's license files, FreeType's license, Apple's GPTK license, and the exact Wine source commit are in the archive.

The same steps run locally:

```sh
scripts/fetch-wine-tools.sh TOOLS          # pinned llvm-mingw, Wine Mono, x86_64 FreeType; needs `brew install bison`
WINE_TOOLS=TOOLS WINE_BUILD=BUILD scripts/build-wine.sh INSTALL
WINE_TOOLS=TOOLS scripts/package-runtime.sh INSTALL/usr/local Evaluation_environment_for_Windows_games_4.0_beta_3.dmg DIST VERSION
```

On first start, the app sets itself up in the background: it checks for Rosetta (installing it asks for an administrator password), downloads the runtime named in `Sources/ArchwayCore/Resources/runtime.json` and checks its SHA-256, creates the bottle, and installs Windows Steam silently from Valve's installer. An already configured runtime is kept. A small toolbar capsule shows progress until setup is done. The app installs a Steam game by writing an app manifest that asks Steam for an update and starting Steam with `-silent`; Steam then downloads the game in the background, and games also start through `-silent`. Without a remembered sign-in, Steam shows its own login window once. Open Steam from the Archway menu or the settings for anything else. Everything Archway sets up lives in its data directory; downloads go to the system's temporary folder. Moving the app to the Trash leaves that data on the disk, because macOS gives apps no uninstall hook, so the app's settings show how much space Archway takes and offer Remove Archway, which ends Archway's Wine sessions, deletes the data directory with its bottles and games, the app's caches, web data, and settings, and moves the app to the Trash. To try a first start without touching your data, launch the bundle with `open --env ARCHWAY_DATA_DIR=/absolute/empty/dir .build/Archway.app`; while the runtime release is private, add `--env ARCHWAY_RUNTIME_ARCHIVE=/absolute/path/to/archway-wine-VERSION.tar.xz`.

Wine is LGPL, so whoever receives the runtime must be able to get its source; `Leafline-Labs/archway-wine` has to be public, or the source offered otherwise, before the package is shared.

### Steam's black window

Under Wine's macOS driver, Windows Steam's client window stays black: Chromium's GPU process draws into a window owned by Steam's browser process, and `winemac.drv` cannot present drawing from another process ([Wine bug 35456](https://bugs.winehq.org/show_bug.cgi?id=35456), [60263](https://bugs.winehq.org/show_bug.cgi?id=60263)). `open-steam`, `install-game`, and `launch-game` therefore install a small shim: Valve's `bin/cef/cef.win64/steamwebhelper.exe` moves to `steamwebhelper.real.exe`, and the shim takes its place and starts it with `--in-process-gpu`. Steam then starts with `-noverifyfiles -norepairfiles`, because its bootstrapper would otherwise restore the original file. A Steam update can still replace the shim during a running session; the next `open-steam` reinstalls it with the updated helper. `doctor` shows the shim state, and `open-steam --without-webhelper-shim` restores Valve's helper for comparison. Directly after `install-steam`, Steam has not downloaded its webhelper yet; let the first start finish updating, then run `close-steam` and `open-steam`.

The shim's source is `Shims/steamwebhelper/steamwebhelper_shim.c`. `Shims/steamwebhelper/build.sh` rebuilds the bundled `Sources/ArchwayCore/Resources/steamwebhelper-shim.exe` with [Zig](https://ziglang.org) (`ZIG=/path/to/zig` if it is not on `PATH`); the build is reproducible. This is a workaround until Wine can present cross-process drawing on macOS.

`open-steam --disable-cef-gpu` passes the single Steam argument `-cef-disable-gpu`. `open-steam --wine-renderer gl` sets `WINE_D3D_CONFIG=renderer=gl` only for that Steam launch. The two options can be combined, but test them separately first to isolate the cause of a black Steam window. These are Steam UI diagnostics, not validated game profiles. Restart Steam first so a previously running instance cannot ignore startup options. `close-steam` sends Steam's cooperative `-shutdown` request within the owned bottle and waits up to 30 seconds for that bottle's Wine server. It does not force-stop Wine clients; a timeout can also mean another Wine service kept the server active.

`open-steam --cef-debugging` adds `-cef-enable-debugging` for temporary CEF diagnostics. With it, `--cef-debug-port PORT` adds `-devtools-port PORT` for a chosen port from 1024 through 65535; this hidden override is present in Steam's installed binary but remains unverified until a live listener check. The default debug port is unchanged when no port is supplied. These options are off by default, can be combined with the other launch options, and are never saved to configuration. Check that the chosen port is free and that any listener binds only to localhost before inspecting it. Close Steam after diagnosis so the debugging endpoint is no longer available.

### D3DMetal

D3DMetal translates Direct3D 11 and 12 to Metal. It needs a Wine runtime with CrossOver's Mac driver interface (`macdrv_functions`), which upstream Wine does not provide; the verified runtime is Whisky's CrossOver-based Wine 11.17 (`runtime-overlays/winecx-gptk-4.7.3`). For local setups, download Apple's *Evaluation environment for Windows games* yourself and point Archway at its `redist/lib`. Its license (4.0 beta 3, §2A(iii) and §2C) allows distributing D3DMetal and the other `redist` components for non-commercial purposes only, unmodified and with Apple's notices. Archway's runtime package relies on that permission (see [Runtime package](#runtime-package)).

```sh
archway check-d3dmetal --redist-lib REDIST_LIB
archway stage-d3dmetal --redist-lib REDIST_LIB --runtime-root DATA/runtime-overlays/RUNTIME/Wine
archway configure --wine DATA/runtime-overlays/RUNTIME/Wine/bin/wine --wineserver DATA/runtime-overlays/RUNTIME/Wine/bin/wineserver --backend d3dmetal --d3dmetal-dir REDIST_LIB
archway launch-game
archway restore-d3dmetal --redist-lib REDIST_LIB --runtime-root DATA/runtime-overlays/RUNTIME/Wine
```

Only a runtime clone inside the data directory's `runtime-overlays/` can be staged. Staging copies `D3DMetal.framework` and `libd3dshared.dylib` into `lib/external`, replaces the runtime's `d3d11`, `d3d12`, `d3d12core`, and `dxgi` builtins, and keeps the originals in a backup directory for `restore-d3dmetal`. Normal staging requires the runtime's `WhiskyWineVersion.plist` (beside `Wine/`) to declare `gptkCapable`; `--allow-unverified-runtime` is for isolated probes only, and such a runtime cannot be configured for launches. `bin/wine` may be a symlink to the loader.

With `--backend d3dmetal`, `launch-game` prepares Brick by Brick on first use: it moves game-local DXVK DLLs to `graphics-backups/brick-by-brick` and sets game-only Wine `DllOverrides` for `d3d10`, `d3d11`, `d3d12`, `d3d12core`, and `dxgi` to `builtin` for `BrickByBrick.exe`. Steam itself is not switched to D3DMetal by these overrides.

The CrossOver-based runtime uses the Windows user name `crossover`, so the bottle's profile moves from `drive_c/users/<you>` to `drive_c/users/crossover`. Copy `AppData/LocalLow/PaperPixelGames` (saves) once after switching; Steam asks for one new sign-in because its stored login is bound to the old profile. `DXVK` remains selectable with `--backend dxvk --dxvk-config FILE --vulkan-icd FILE`.

`doctor` reads state without creating the data directory. `init-bottle` waits at most five minutes for `wine wineboot -u`, then up to 30 seconds for Wine's registry file, which may appear after the command exits. It marks the bottle as owned before setup and ready only after both checks pass. An incomplete owned setup can be retried. Archway refuses to adopt an existing unmarked Wine prefix. On setup timeout it signals only the process group it started; Wine may leave a separately daemonized wineserver, which Archway does not stop. Installer, Steam, and game commands dispatch a GUI request and write subprocess output to a log. Repeated requests truncate a log once it exceeds 10 MiB; an active GUI process may still grow its log beyond that size. A sent request does **not** prove installation, process lifetime, or playability. After Steam login and game installation, manually test actual play, save, quit, relaunch, and save reload. Compatibility remains unverified until that sequence passes on the target Mac.

GUI requests start Wine with the working directory set to the validated Windows installer or Steam executable's folder, matching the packaged Wine app's file-open behavior. Bottle setup and wineserver wait keep their normal working directory.

The Swift Testing suite checks persisted configuration, executable and installer paths, owned bottle and log scope, Steam arguments and URI, environment isolation, app IDs, and setup process failure and timeout behavior using local fake executables. It does not exercise Wine or Steam. This Command Line Tools installation needs the explicit macro-library flag shown above; a full Xcode toolchain can use plain `swift test`. With the first game's manual gate passed, the next step is the SwiftUI app with the owned Steam library and per-game profiles.
