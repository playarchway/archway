# Wine runtime probe

This is the record of how Archway's runtime came together in October 2026, kept for its findings. Paths use Archway's naming; "the user" is the developer testing on their own Mac. For the current setup, see the [README](../README.md).

On macOS 27.0.1 (arm64, Apple Silicon), Gcenx Wine Staging 11.18 ran under the available x86_64 translation without changing macOS security settings. This was a runtime smoke probe only; it does not establish Steam or game compatibility.

## Runtime and commands

- Upstream release: [Gcenx macOS Wine builds, 11.18](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18)
- Source archive: [wine-staging-11.18-osx64.tar.xz](https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-staging-11.18-osx64.tar.xz)
- Downloaded to `~/Library/Application Support/Archway/runtime-probe/wine-staging-11.18-osx64.tar.xz` (193,105,336 bytes); SHA-256 `b63704b91af269bc026a87f12bd297c4a50caaf570c322e600b6621ef918f127`, matching the release API digest.
- Extracted app: `~/Library/Application Support/Archway/runtime-probe/extracted/Wine Staging.app`
- Runtime bin directory: `~/Library/Application Support/Archway/runtime-probe/extracted/Wine Staging.app/Contents/Resources/wine/bin`
- `wine`, `wineboot` (symlink to `wine`), and `wineserver` are present there. No `wine64` binary was present.
- With a fresh `WINEPREFIX=~/Library/Application Support/Archway/runtime-probe/bottle` and inherited Wine/DYLD overrides cleared, absolute `wine --version` returned exit 0 and `wine-11.18 (Staging)`. Absolute `wineboot --init` returned exit 0 and created the prefix. Its log includes Wine service/RPC errors and common-controls warnings despite the successful exit, so treat initialization as a basic smoke result, not proof every Wine component works.

Logs are at `~/Library/Application Support/Archway/runtime-probe/wine-version.log` and `wineboot.log`. The extracted app used about 843 MiB; the prefix about 330 MiB; archive about 184 MiB; probe directory about 1.33 GiB total.

## Limits

`/Library/Frameworks/GStreamer.framework` was absent. Wine version reporting and prefix initialization worked without it, but multimedia playback is untested; upstream package guidance lists GStreamer as a dependency. Steam installation/login, Steam UI or background operation, Brick by Brick (Steam app 5228920), saves/reloads, DXMT, and game rendering/input are all untested. Do not infer game compatibility from this probe.

## Rosetta and macOS 28

The user observed a macOS 28 compatibility warning while Wine started. This runtime is an x86_64 macOS executable and relies on Rosetta. [Apple documents general Rosetta availability through macOS 27](https://support.apple.com/en-us/102527); from macOS 28, support is restricted to certain older, unmaintained games relying on Intel frameworks. Apple's statement does not establish that this Wine runtime or Windows games hosted by it qualify for that exception.

The current target remains macOS 27.0.1. A native ARM Swift/SwiftUI launcher does not remove the helper runtime's translation dependency. Keep the runtime replaceable and treat macOS 28 compatibility as unverified; do not suppress or bypass the warning as a compatibility fix.

## Archway CLI integration

The Swift CLI was configured to use this extracted runtime and its sibling `wineserver`. It created its own separate bottle at `~/Library/Application Support/Archway/bottles/steam-5228920` with an Archway ownership marker. The original smoke-test prefix remains separate.

The first `init-bottle` invocation exposed a timing issue: Wine returned before `system.reg` had been written. The registry appeared about six seconds later. The CLI now waits up to 30 seconds for a nonempty, regular registry file before transitioning its marker from `initializing` to `ready`. A subsequent real `init-bottle` succeeded, and `doctor` confirmed the configured runtime and ready owned bottle. Eight automated tests passed, including delayed registry creation, unowned prefixes, symlinked logs, and setup timeout cleanup. The test command and the local Command Line Tools macro-plugin workaround are in the [README](../README.md).

The official Valve [Windows Steam installer](https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe), linked from [Steam's download page](https://store.steampowered.com/about/), was downloaded to `~/Library/Application Support/Archway/downloads/SteamSetup.exe` (2,380,800 bytes, SHA-256 `7d3654531c32d941b8cae81c4137fc542172bfa9635f169cb392f245a0a12bcb`). Its PE header was checked; its Authenticode signature was not verified. The CLI dispatched the installer in the owned bottle. The user confirmed that Steam installed and updated, but its window remained black. Login and game execution are not confirmed.

Setup timeout cleanup targets the process group created by Archway and reaps its direct child after signaling. A Wine process that daemonizes outside that group may remain running; the CLI does not use a global Wine kill operation.

## Steam black-window investigation

Steam's CEF logs initially reported ANGLE/DXGI adapter-query errors and rejection of a requested GLES 3.0 context where GLES 2.0 was reported. Steam then disabled GPU acceleration at runtime. Two controlled restarts were tested on the existing Wine 11.18 bottle:

1. `open-steam --disable-cef-gpu` passed `-cef-disable-gpu` to Steam. Fresh logs confirmed software compositing and no repeated GLES error, but the user still saw a black window.
2. `open-steam --wine-renderer gl` requested `WINE_D3D_CONFIG=renderer=gl` without the previous Steam flag. The GPU errors returned and the user again saw a black window. The environment override is covered by command-construction tests; the Steam logs do not independently record it.

Before each restart, `close-steam` sent a cooperative shutdown request and the configured `wineserver -w` confirmed that the owned prefix's server exited. No force stop or native macOS Steam command was used. The old Windows Steam session was closed again after both unsuccessful attempts, and its installation was retained.

The CLI's nine tests pass, including scoped launch environment, diagnostic options, and executable working directories. These flags are diagnostic controls, not a validated game profile. A separate Wine Sikarugir 10 engine was briefly probed, but the user requires current Wine and Steam versions rather than a downgrade workaround. No Steam was installed with Wine 10.

At the user's request, the entire `runtime-probe/sikarugir10` subtree was removed: archive, extracted engine, staged support libraries, probe prefix, and logs (about 1.23 GiB allocated before deletion). No Wine 10 process was active and the current runtime configuration did not reference it. No Wine 10 packages were installed globally. Wine 11.18, its existing Steam installation, and the active Archway configuration were preserved. Investigation continues with current releases.


## Current-version policy and launcher correction

The user requires current Wine and Steam versions; an older-runtime workaround is not the product target. On 2026-10-23, the newest published [Gcenx macOS packages](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18) are 11.18, while [WineHQ source 11.20](https://dl.winehq.org/wine/source/11.x/wine-11.20.tar.xz) is available. No Wine source build has been run. The release difference does not establish that 11.20 fixes this Steam issue.

Inspection found that Wine's own macOS EXE launcher sets its working directory to the executable's parent. Archway previously inherited the CLI's directory. GUI requests now use the validated installer or Steam executable's parent as their per-process working directory. This is covered by a real fake-process test recording its directory; no process-global directory is changed. The user confirmed that both this corrected launch and a direct manual Wine invocation still showed a black window. The installer and update-downloader windows had rendered correctly.

## CEF content versus window presentation

The installed Steam client contains the `-devtools-port` option. A controlled launch with `-cef-enable-debugging -devtools-port 15873` successfully opened a listener on **127.0.0.1:15873 only**. Port 8080 belongs to an unrelated OrbStack process and was left untouched. These diagnostic flags are transient, not saved into the runtime configuration.

Read-only inspection through CEF's local debugging interface found a login-page target titled `Bei Steam anmelden`. Its document state was `complete` and visibility `visible`, with 71 DOM elements, text and password inputs, one button, and a loaded image. No field values, cookies, account/session files, or QR data were read or recorded.

An internal `Page.captureScreenshot` produced a 700 by 440 image with rendered content (non-black pixel fraction 1.0 at a channel threshold of 8; mean color channel approximately 60.75). Only image statistics were returned; no login screenshot was saved. The user confirmed that the outer macOS window remained black during this same launch. This establishes that the browser can load and paint the login content, while visible window presentation is failing. The diagnostic Steam session and browser tab were subsequently closed.

## Relevant launcher references

- [frankea/Whisky](https://github.com/frankea/Whisky) separates Chromium launchers' graphics backend from games: its resolver selects DXVK for Steam/CEF and its Wine registry code applies per-executable overrides. Its packaged runtime is based on Wine 11.0, so it is a design/configuration reference, not a newer runtime replacement. [Resolver](https://github.com/frankea/Whisky/blob/main/WhiskyKit/Sources/WhiskyKit/Wine/GraphicsBackendResolver.swift), [override implementation](https://github.com/frankea/Whisky/blob/main/WhiskyKit/Sources/WhiskyKit/Wine/WineDLLOverrideRegistry.swift).
- [Mythic](https://github.com/MythicApp/Mythic) is useful for runtime release metadata and cancellable installation-operation state. Its current source includes a checksum-verification TODO; that omission should not be copied into Archway.
- [Heroic](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher) separates library metadata from store-specific installation/launch managers. That boundary is relevant to Archway's complete owned-game catalog; it does not imply changing the selected SwiftUI stack or adopting Heroic's stores as Steam support.
- [Kegworks now redirects to Sikarugir](https://github.com/Sikarugir-App/Sikarugir). Its renderer/support template is informative, but its listed Wine 11.0 engine is not newer than the current 11.18 package and has a reported macOS 27 external-launch issue.

No code from these applications has been copied into Archway. Their app and runtime-component licenses must be evaluated separately before any future source or binary reuse.

## DXVK 3.1 comparison: unsuccessful for Steam CEF

A [MetalSharp DXVK-MacOS v3.1-macos1.0](https://github.com/metalsharp/DXVK-MacOS/releases/tag/v3.1-macos1.0) archive was staged and verified against its release API SHA-256 (`8b37482116da0136b2b4feaa0118f9441bcf148b9532de474edc5a89c3e55687`). Its Wine portability patch matches the functional change that Gcenx lists as applied to Wine 11.18; no Wine rebuild was performed.

The test used an APFS copy-on-write clone at `~/Library/Application Support/Archway/graphics-probe/metalsharp-3.1/archway/bottles/steam-5228920`. Its configuration retained the same Wine 11.18 executables and used the staged MoltenVK/ICD and DXVK config. Only the clone's system32 `d3d11.dll` and `dxgi.dll` were replaced, with originals backed up and symlink-safe atomic replacement. Global load order was explicitly builtin, with native-then-builtin overrides for `steam.exe` and `steamwebhelper.exe` only. Both executables were verified as x86-64. Original-prefix DLL hashes remained unchanged.

Logs proved DXVK `v3.1+` loaded, MoltenVK 1.4.3 identified the Apple M5 Pro, and Vulkan device creation succeeded. The failure then became explicit: `DxgiFactory::CreateSwapChainForComposition: Not implemented`, followed by shared-image backing/Skia failures and GPU-process crashes. The user confirmed that the external Steam window still remained black. The test session was closed cleanly with the clone-scoped shutdown/wineserver wait; no Wine process was force-killed.

This renderer comparison did not solve Steam's UI. It does not establish that DXVK cannot run a game's ordinary window swap chain. No game was installed or launched, and no downgrade of Wine or Steam occurred.


## Root cause and shipped workaround

On 2026-10-23 the black window was traced to cross-process presentation. Steam's webhelper draws each client window through SDL3 in its browser process, but the page pixels come from Chromium's separate GPU/viz process, which paints into the browser-owned HWND. In Wine 11.18 `win32u/dce.c` gives such a cross-process DC no window surface, and `winemac.drv` has no `pGetDC` hook (unlike `winex11.drv`), so the drawing is discarded. Wine 11.20 and `master` (checked the same day) are unchanged in this respect; 11.20 only adds `todo_wine` OpenGL tests for rendering into another process's window. Related reports: [Wine bug 35456](https://bugs.winehq.org/show_bug.cgi?id=35456) (GDI side), [Wine bug 60263](https://bugs.winehq.org/show_bug.cgi?id=60263) (Metal side), [Gcenx issue #170](https://github.com/Gcenx/macOS_Wine_builds/issues/170).

Ruled out in an APFS clone of the bottle: forcing `SDL_RENDER_DRIVER=software`, and disabling `opengl32` for `steamwebhelper.exe` only. Confirmed: starting the browser webhelper with `--in-process-gpu` (via a wrapper at Steam's helper path, Steam started with `-noverifyfiles -norepairfiles`) renders the complete login window; screenshots were checked directly. Without `-noverifyfiles` Steam restores its helper at startup.

Archway now installs this shim automatically (see the README). Verified on the real `steam-5228920` bottle through `archway open-steam`: the login window renders, no separate GPU process runs, a cooperative `steam.exe -shutdown` lets the Wine server exit within about 6 seconds, and killing the shim also ends the real helper through a kill-on-close job object. Login, game installation, and play are still untested.


## D3DMetal on a CrossOver-based runtime (verified)

Brick by Brick's Unity build could not create a Direct3D 11 device with Wine's builtin `wined3d` (`80004005`). DXVK 3.1 rendered the menu, but mouse and keyboard input did not reach the game. Apple's D3DMetal (GPTK 4.0 beta 3, user-downloaded) was then staged into an Archway-owned copy of Whisky's CrossOver-based Wine 11.17 runtime and configured with `--backend d3dmetal`. On 2026-10-23, in the real `steam-5228920` bottle, Unity reported `Direct3D 11.0 [level 11.1]`, `Renderer: AMD Compatibility Mode`, and the user confirmed menu input, play, save, and reload. Steam keeps the webhelper shim on this runtime: a cloned bottle without the shim still showed a black Steam window.

Switching runtimes changed the Windows profile to `users/crossover`; saves were copied from the previous `users/<name>` profile, and Steam required one new sign-in. The previous configuration is kept as `config.before-d3dmetal.json`.

## Archway's own Wine 11.20

A separate build of upstream Wine 11.20, now [archway-wine](https://github.com/playarchway/archway-wine), carries a cross-process GDI fix, with which Steam renders and signs in without the shim. D3DMetal needs CrossOver's exported `macdrv_functions` table; its 24-entry layout follows CrossOver's Mac driver, whose Wine source CodeWeavers publishes under the LGPL ([CrossOver source](https://www.codeweavers.com/crossover/source)), and is reimplemented in `dlls/winemac.drv/d3dmetal.c`. All other Wine symbols D3DMetal looks up already exist upstream. Brick by Brick first crashed early on a thread Wine did not create; two `ntdll` fixes keep the native pthread GS base for D3DMetal's threads and give `gmtime` its own storage. With them, Brick by Brick runs on this build.

On 2026-10-25 this build became Archway's default runtime, shipped as a downloadable package with FreeType, Wine Mono, and D3DMetal (see the README). Wine's Windows user is the Mac user name again instead of `crossover`, so saves moved back to that profile; Steam kept its sign-in.
