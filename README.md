# Overcross technical proof of concept

Overcross is a Swift command-line core for testing **Brick by Brick: Tidy Up the Small Town!** (Steam app `5228920`) in a dedicated Wine bottle on macOS. It does not bundle Wine, Steam, or a game. Its library target is intended for a later native SwiftUI app.

## Prerequisites and commands

Install or select a freely usable macOS Wine runtime separately, and download the official **Windows** Steam installer yourself. Use absolute local paths. Overcross never requests your Steam credentials; sign in through the Windows Steam window.

```sh
# With the installed macOS Command Line Tools (Swift 6.4):
swift test -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
swift run overcross help
swift run overcross doctor
swift run overcross configure --wine '/absolute/path/to/wine' --wineserver '/absolute/path/to/wineserver'
swift run overcross init-bottle
swift run overcross install-steam --installer '/absolute/path/to/SteamSetup.exe'
swift run overcross doctor
swift run overcross open-steam
swift run overcross open-steam --without-webhelper-shim
swift run overcross close-steam
swift run overcross open-steam --disable-cef-gpu
swift run overcross open-steam --wine-renderer gl
swift run overcross install-game
swift run overcross launch-game
swift run overcross locations
```

`--wineserver` is optional for normal launches but required for `close-steam`. The default game ID is `5228920`; `install-game` and `launch-game` also accept `--app-id` with a positive 32-bit Steam ID. Add `--data-dir '/absolute/path'` to any command for an isolated local probe. The normal data directory is `~/Library/Application Support/Overcross`; it contains `config.json`, `bottles/steam-5228920`, and `logs/`. Overcross uses only this bottle as `WINEPREFIX`. It does not modify the native macOS Steam installation.

Some local Wine builds require a separate directory of support libraries. If your selected runtime needs one, add `--library-dir '/absolute/path/to/support-libs'` to `configure`. Overcross validates and saves one existing directory, then sets `DYLD_LIBRARY_PATH` to that directory for its Wine and wineserver requests. Inherited DYLD variables remain excluded. This is an optional local runtime setting, not a validated runtime distribution.

For a separate renderer experiment, `configure` also accepts `--dxvk-config '/absolute/path/to/dxvk.conf' --vulkan-icd '/absolute/path/to/icd.json'`. Supply both existing readable files or neither. Overcross saves their canonical paths and sets `DXVK_CONFIG_FILE` and `VK_ICD_FILENAMES` only from that configuration for its Wine requests; inherited DXVK and Vulkan variables remain excluded. This is an opt-in probe, not a validated game profile. Use a separate `--data-dir` to keep the current bottle and configuration untouched.

As an alternative to the interactive installer command above, add `--silent` to pass only NSIS `/S` to the locally supplied Windows installer. The installer chooses its normal location. Both modes dispatch a request; check `doctor` for the Steam executable afterward. Steam account login still happens in the Windows Steam GUI.

### Steam's black window

Under Wine's macOS driver, Windows Steam's client window stays black: Chromium's GPU process draws into a window owned by Steam's browser process, and `winemac.drv` cannot present drawing from another process ([Wine bug 35456](https://bugs.winehq.org/show_bug.cgi?id=35456), [60263](https://bugs.winehq.org/show_bug.cgi?id=60263)). `open-steam`, `install-game`, and `launch-game` therefore install a small shim: Valve's `bin/cef/cef.win64/steamwebhelper.exe` moves to `steamwebhelper.real.exe`, and the shim takes its place and starts it with `--in-process-gpu`. Steam then starts with `-noverifyfiles -norepairfiles`, because its bootstrapper would otherwise restore the original file. A Steam update can still replace the shim during a running session; the next `open-steam` reinstalls it with the updated helper. `doctor` shows the shim state, and `open-steam --without-webhelper-shim` restores Valve's helper for comparison. Directly after `install-steam`, Steam has not downloaded its webhelper yet; let the first start finish updating, then run `close-steam` and `open-steam`.

The shim's source is `Shims/steamwebhelper/steamwebhelper_shim.c`. `Shims/steamwebhelper/build.sh` rebuilds the bundled `Sources/OvercrossCore/Resources/steamwebhelper-shim.exe` with [Zig](https://ziglang.org) (`ZIG=/path/to/zig` if it is not on `PATH`); the build is reproducible. This is a workaround until Wine can present cross-process drawing on macOS.

`open-steam --disable-cef-gpu` passes the single Steam argument `-cef-disable-gpu`. `open-steam --wine-renderer gl` sets `WINE_D3D_CONFIG=renderer=gl` only for that Steam launch. The two options can be combined, but test them separately first to isolate the cause of a black Steam window. These are Steam UI diagnostics, not validated game profiles. Restart Steam first so a previously running instance cannot ignore startup options. `close-steam` sends Steam's cooperative `-shutdown` request within the owned bottle and waits up to 30 seconds for that bottle's Wine server. It does not force-stop Wine clients; a timeout can also mean another Wine service kept the server active.

`open-steam --cef-debugging` adds `-cef-enable-debugging` for temporary CEF diagnostics. With it, `--cef-debug-port PORT` adds `-devtools-port PORT` for a chosen port from 1024 through 65535; this hidden override is present in Steam's installed binary but remains unverified until a live listener check. The default debug port is unchanged when no port is supplied. These options are off by default, can be combined with the other launch options, and are never saved to configuration. Check that the chosen port is free and that any listener binds only to localhost before inspecting it. Close Steam after diagnosis so the debugging endpoint is no longer available.

### D3DMetal runtime experiment

`check-d3dmetal --redist-lib '/absolute/path/to/redist/lib'` validates a local Apple Game Porting Toolkit redist. For the 4.0 beta 3 payload it checks the x64 Windows forwarders `d3d11`, `d3d12`, `d3d12core`, and `dxgi`, their matching Unix bridges, `libd3dshared.dylib`, and `D3DMetal.framework`. Apple components are not bundled with Overcross. Only a separately cloned Wine runtime inside the selected data directory's `runtime-overlays/` may be staged:

```sh
overcross stage-d3dmetal --redist-lib '/absolute/path/to/redist/lib' --runtime-root '/absolute/Overcross/data/runtime-overlays/compatible-wine'
overcross restore-d3dmetal --redist-lib '/absolute/path/to/redist/lib' --runtime-root '/absolute/Overcross/data/runtime-overlays/compatible-wine'
```

Staging preserves replaced components in `.overcross-d3dmetal-backup` inside that clone and restores only matching files. A provider's `gptkCapable` metadata permits normal staging. `--allow-unverified-runtime` permits an isolated diagnostic overlay without asserting compatibility; normal `configure --backend d3dmetal --wine CLONED_RUNTIME/bin/wine --d3dmetal-dir REDIST_LIB` and launch requests reject unverified or unstaged runtimes. A staged label is not evidence that Apple's modules loaded or a game works. DXVK remains selectable with `--backend dxvk --dxvk-config FILE --vulkan-icd FILE`; D3DMetal selection excludes these variables.

Brick by Brick also requires removing game-local DXVK DLLs and setting game-only Wine `DllOverrides` for `d3d11`, `d3d12`, `d3d12core`, and `dxgi` to `builtin` while its bottle is stopped. `launch-game` refuses a D3DMetal selection if any of those local DLLs or exact game-only builtin overrides are missing. The current runtime experiment does not automatically change the live bottle's registry or game directory; preserve its backup and prepare only a separate owned probe bottle. Steam's webhelper shim remains a separate Steam UI workaround. Manual mapped-module and game graphics log evidence are required before calling a backend operational.

`doctor` reads state without creating the data directory. `init-bottle` waits at most five minutes for `wine wineboot -u`, then up to 30 seconds for Wine's registry file, which may appear after the command exits. It marks the bottle as owned before setup and ready only after both checks pass. An incomplete owned setup can be retried. Overcross refuses to adopt an existing unmarked Wine prefix. On setup timeout it signals only the process group it started; Wine may leave a separately daemonized wineserver, which Overcross does not stop. Installer, Steam, and game commands dispatch a GUI request and write subprocess output to a log. Repeated requests truncate a log once it exceeds 10 MiB; an active GUI process may still grow its log beyond that size. A sent request does **not** prove installation, process lifetime, or playability. After Steam login and game installation, manually test actual play, save, quit, relaunch, and save reload. Compatibility remains unverified until that sequence passes on the target Mac.

GUI requests start Wine with the working directory set to the validated Windows installer or Steam executable's folder, matching the packaged Wine app's file-open behavior. Bottle setup and wineserver wait keep their normal working directory.

The Swift Testing suite checks persisted configuration, executable and installer paths, owned bottle and log scope, Steam arguments and URI, environment isolation, app IDs, and setup process failure and timeout behavior using local fake executables. It does not exercise Wine or Steam. This Command Line Tools installation needs the explicit macro-library flag shown above; a full Xcode toolchain can use plain `swift test`. The owned Steam library UI and Steam Web API catalog are deferred until this first game passes the manual gate.
