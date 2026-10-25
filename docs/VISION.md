# Vision

Archway is a free, open-source macOS app for playing Windows games on Apple silicon Macs without a Windows installation. It does not build its own Windows compatibility layer. Its value lies in combining existing technology, Wine, Rosetta, and Apple's D3DMetal, into a library that sets games up automatically and stays out of the player's way.

**Install less. Configure less. Play more.**

## Who it is for

- People with an Apple silicon Mac who want to play their Windows games, starting with indie titles whose hardware needs a current Mac easily meets.
- Players whose games live on Steam today, and later on GOG, itch.io, Epic Games, or as local installers.
- People who prefer a free and transparent tool over a paid one.

Wine setups, graphics backends, and Windows dependencies are confusing for casual players, and a game that could run often fails because of one wrong bottle, DLL, or graphics setting. Archway takes those decisions off the player's hands for games it knows, and makes experiments traceable for games it doesn't.

## Promise

- **Tested games** start with a known configuration and no manual steps.
- **Unknown games** can be tried, clearly marked as untested, with no promise that they run.
- **One app to install.** Archway downloads its Wine runtime, sets up its Windows environment and Windows Steam in the background, and runs Steam out of sight. Steam's own window appears only when a player signs in for the first time or opens it on purpose.

## Not goals

- Running every Windows game, in particular AAA titles.
- Reimplementing Wine or D3DMetal.
- Kernel drivers, kernel anti-cheat, or arbitrary DRM.
- Being a store, a checkout, or a replacement for the stores' own clients.
- Launching native macOS games or converting Windows games into Mac apps.

## How it fits together

| Part | Role |
| --- | --- |
| **Wine** | Windows APIs on macOS. Archway builds and ships its own Wine with a few macOS patches ([archway-wine](https://github.com/Leafline-Labs/archway-wine)). |
| **Rosetta** | Runs Wine's x86_64 code on Apple silicon. |
| **D3DMetal** | Apple's Direct3D 11 and 12 translation to Metal, from the Game Porting Toolkit. Its license allows non-commercial redistribution, which Archway relies on. |
| **DXVK, WineD3D** | Alternative graphics paths for games that need them. |
| **Windows Steam** | Runs inside Archway's bottle for sign-in, downloads, updates, and launching games; Archway drives it in the background. |
| **Swift and SwiftUI** | The native app and its core library, which the `archway` command line tool shares. |

Compatibility depends on the game, its engine and graphics API, and the versions of every part. Archway targets current Wine and Steam releases; falling back to an older Wine is not a fix.

## Roadmap

**Now:** the Steam library with installed and tested states, background setup, silent Steam installs, launching, and per-game graphics settings, validated end to end with Brick by Brick: Tidy Up the Small Town!

**Next:**

- More tested games with different engines and graphics APIs, each with a stored profile.
- Signed and notarized releases.
- GOG, itch.io, and local installers.
- Managing dependencies that games commonly need, where licenses allow it.

**Later:**

- A community database of tested game profiles and automatic configuration suggestions.
- Diagnosing common start failures from logs.
- Controller profiles, save management, and more stores.

## Risks

| Risk | How Archway handles it |
| --- | --- |
| Rosetta for general use ends after macOS 27; Apple keeps it only for some older games built on Intel frameworks. | Archway's runtime is x86_64 and needs Rosetta. macOS 28 is not promised; the runtime stays replaceable. |
| Graphics compatibility varies by game. | Per-game backends and profiles. |
| Anti-cheat, DRM, or Steam quirks block a game. | Documented per tested game; no blanket promises. |
| Updates break working games. | Versioned runtime packages, pinned per release, with a way back. |
| Wine and Steam memory and storage use. | Measured separately from the app itself; the app shows its storage and removes everything on request. |
