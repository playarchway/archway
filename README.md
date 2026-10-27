# Archway

Archway is a free, open-source macOS app for playing Windows games on Apple silicon Macs. It shows your Steam library, installs and starts games with one click, and sets up everything they need, Wine, Windows Steam, and Apple's D3DMetal, in the background.

**Status:** early. Archway runs on macOS 27 on Apple silicon. A game shows as tested once most players report it working; all others are marked untested. There is no public release yet, so build it from source. See the [vision](docs/VISION.md) for where it is heading.

## What it does

- **Your Steam library** in a native app, with installed games up front and every game you own below.
- **Background setup** on first start: Archway checks for Rosetta, downloads its Wine runtime and verifies its checksum, creates a Windows environment, and installs Windows Steam silently. A short introduction explains the basics meanwhile.
- **Installing and playing without Steam's window.** Archway queues a game for Steam and runs Steam with `-silent`, so it downloads in the background while the install button shows the progress. Steam's own window appears only to sign in once, or when you open it from the menu or the settings.
- **Uninstall and clean removal.** Uninstall games from their page. Because macOS runs nothing when an app moves to the Trash, the settings show how much space Archway takes and offer *Remove Archway*, which deletes its data, bottles, and games and then moves the app to the Trash.
- **Your own Windows games:** add an `.exe` from your Mac.

## Build and run

You need macOS 15 or later on Apple silicon, which Apple's D3DMetal requires (Archway is developed and tested on macOS 27), and Swift 6.4, from Xcode or the Command Line Tools.

```sh
scripts/build-app.sh            # builds .build/Archway.app (add `release` for an optimized build)
open .build/Archway.app
swift test                      # with only the Command Line Tools, see docs/CLI.md for the extra flag
```

On first start Archway downloads its runtime (about 145 MB) and Windows Steam. Everything it sets up lives in `~/Library/Application Support/Archway`; downloads go to the system's temporary folder.

To try a first start without touching your data, launch the bundle with an empty data directory:

```sh
open --env ARCHWAY_DATA_DIR="$HOME/Library/Application Support/Archway/first-start-test" .build/Archway.app
```

`--env ARCHWAY_RUNTIME_ARCHIVE=/path/to/archway-wine-VERSION.tar.xz` uses a local runtime package instead of downloading one, and `--env ARCHWAY_INTRO_PAGE=0…3` opens the introduction at a page.

## How it works

Archway runs games through [Wine](https://www.winehq.org), with [archway-wine](https://github.com/playarchway/archway-wine), a Wine 11.20 build with a few macOS patches that let Apple's D3DMetal translate Direct3D 11 and 12 to Metal. The [runtime package](docs/RUNTIME.md) bundles that Wine with FreeType, Wine Mono, and D3DMetal. Windows Steam runs inside Archway's bottle for sign-in, downloads, and launching games; a small shim keeps its window from staying black under Wine's macOS driver.

| Folder | Contents |
| --- | --- |
| `Sources/Archway` | The SwiftUI app |
| `Sources/ArchwayCore` | Bottles, runtimes, Steam, and processes; shared by the app and the CLI |
| `Sources/ArchwayCLI` | The [`archway` command line tool](docs/CLI.md) for development and diagnosis |
| `Shims/steamwebhelper` | The Steam webhelper shim |
| `scripts` | Building the app, the Wine runtime, and the runtime package |
| `docs` | [Vision](docs/VISION.md), [command line tool](docs/CLI.md), [runtime package](docs/RUNTIME.md), and the [runtime probe log](docs/RUNTIME_PROBE.md) |

## Contributing

Bug reports, game test results, and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues privately as described in [SECURITY.md](SECURITY.md).

## License

Archway is licensed under the [GNU General Public License v3.0](LICENSE).

The runtime package that Archway downloads contains third-party software under its own terms:

- **Wine** ([archway-wine](https://github.com/playarchway/archway-wine)): GNU LGPL 2.1 or later.
- **FreeType**: FreeType License.
- **Wine Mono**: MIT and LGPL components.
- **D3DMetal** from Apple's Game Porting Toolkit: Apple's license, which permits redistribution for non-commercial purposes only. Archway is free and non-commercial; anyone redistributing the runtime package must respect this.

Archway is not affiliated with Apple, Valve, or CodeWeavers. Steam is a trademark of Valve Corporation. Archway never asks for your Steam password; you sign in on Steam's own pages and windows.
