# Contributing

Thanks for helping Archway. Bug reports, results from testing games, and pull requests are all welcome.

Everyone taking part follows our [code of conduct](https://github.com/playarchway/.github/blob/main/CODE_OF_CONDUCT.md).

## Reporting a game

Tell us which game you tried (with its Steam app ID), your Mac and macOS version, and how far it got: installs, starts, plays, saves, reloads after a restart. Attach the game's log from *Advanced… → Export Log*. A game counts as tested only after that whole sequence passes.

## Working on the code

1. Build and run the app with `scripts/build-app.sh` and `open .build/Archway.app`; quit a running Archway first. The bare SwiftPM binary has no localizations and stores its settings elsewhere.
2. Run `swift test` before you open a pull request. With only the Command Line Tools installed, add the flag from [docs/CLI.md](docs/CLI.md).
3. Try changes that touch Wine or Steam in a bottle of your own, not your everyday one: point the app at another data directory with `ARCHWAY_DATA_DIR`, or the CLI with `--data-dir`. [AGENTS.md](AGENTS.md) explains how to keep parallel Wine sessions apart.

Keep changes small and focused, and match the style of the code around them.

- **Commits** follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/), for example `feat(app): …` or `fix(steam): …`. Releases and the changelog come from them.
- **UI text** is written in English in code. Every new string needs a German translation in `Sources/Archway/Resources/Localizable.xcstrings`. Strings that are not literals passed to SwiftUI views use `String(localized:)`.
- **Wine changes** go to [archway-wine](https://github.com/playarchway/archway-wine); [archway-runtime](https://github.com/playarchway/archway-runtime) builds the runtime package from it.

By contributing, you agree that your contributions are licensed under the [GPL-3.0](LICENSE).
