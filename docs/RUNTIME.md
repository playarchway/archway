# Runtime package

The Runtime workflow (`.github/workflows/runtime.yml`, started by hand on a macOS runner) builds the runtime that Archway is meant to download: our Wine tree from `playarchway/archway-wine`, FreeType 2.15.0, Wine Mono 11.3.0 (shared, so new bottles skip the Mono download dialog), and D3DMetal staged on top. Apple's Game Porting Toolkit comes from the private repository `playarchway/archway-build-inputs`, which Archway Bot reads. It publishes `archway-wine-VERSION.tar.xz` with a SHA-256 file as a `runtime-VERSION` prerelease. The archive holds `Wine/` and `WhiskyWineVersion.plist`; unpack it to `DATA/runtime-overlays/NAME/` and configure Archway with `--library-dir` and `--d3dmetal-dir` both set to `DATA/runtime-overlays/NAME/Wine/lib`. Wine's license files, FreeType's license, Apple's GPTK license, and the exact Wine source commit are in the archive.

The same steps run locally:

```sh
scripts/fetch-wine-tools.sh TOOLS          # pinned llvm-mingw, Wine Mono, x86_64 FreeType; needs `brew install bison`
WINE_TOOLS=TOOLS WINE_BUILD=BUILD scripts/build-wine.sh INSTALL
WINE_TOOLS=TOOLS scripts/package-runtime.sh INSTALL/usr/local Evaluation_environment_for_Windows_games_4.0_beta_3.dmg DIST VERSION
```

Wine is LGPL, so whoever receives the runtime must be able to get its source. The archive names the exact commit of [archway-wine](https://github.com/playarchway/archway-wine) it was built from.
