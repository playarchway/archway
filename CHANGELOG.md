# Changelog

## [0.3.0](https://github.com/playarchway/archway/compare/v0.2.0...v0.3.0) (2026-10-29)


### Features

* **library:** explain why a game didn't start ([059538b](https://github.com/playarchway/archway/commit/059538b7f695497b3f9e9fdcf3c5527f1edfde2b))
* **library:** filter and sort the library ([5ac3372](https://github.com/playarchway/archway/commit/5ac3372af9cf59880c2602cac4f81e112255e2da))
* **library:** mark only tested games and those that can't run ([b4258ef](https://github.com/playarchway/archway/commit/b4258efc173df3500b6c0ccd95a5d59681bcd0e0))
* **library:** notify when a game has finished installing ([02a06d3](https://github.com/playarchway/archway/commit/02a06d35038cd677637046b78a04ddce47190684))
* **library:** show screenshots in a full-window viewer ([274c6c7](https://github.com/playarchway/archway/commit/274c6c71d174e36b402fd35244fa2929009c58a7))
* **wine:** install the Microsoft runtimes a game needs before it starts ([5063e16](https://github.com/playarchway/archway/commit/5063e16b5ef00f8684feee893075295c5e8f4203))


### Bug Fixes

* **wine:** stop crashes from leaving Wine's debugger behind ([1209302](https://github.com/playarchway/archway/commit/12093029cf6c046e1f2466cc2017ade89a085222))


### Performance Improvements

* **library:** keep library scrolling smooth ([7c390a0](https://github.com/playarchway/archway/commit/7c390a04e56f001f59c9a59b9e2d689336c71d2d))
* **library:** keep one backdrop behind the library and blur it once ([4b5a996](https://github.com/playarchway/archway/commit/4b5a996c5b88351129f5d7ed4b8c19a6b1f7a23b))

## [0.2.0](https://github.com/playarchway/archway/compare/v0.1.2...v0.2.0) (2026-10-29)


### Features

* **library:** mark games with a Mac version in the library ([c057479](https://github.com/playarchway/archway/commit/c057479abb151bf828c9126507e7fd50590767dd))
* **library:** offer a game's Mac version through Steam for macOS ([2ae0606](https://github.com/playarchway/archway/commit/2ae06067979f757bd69f3261769bc0e3666d053a))


### Bug Fixes

* **build:** stamp the app with the SDK it links against ([e482369](https://github.com/playarchway/archway/commit/e4823692a737ca105868928f4fa5e45f1c85c978))
* **library:** let the toolbar's glass be the search field's background ([9272504](https://github.com/playarchway/archway/commit/9272504bbe764dbe6e9de5b507544941f0a02b87))

## [0.1.2](https://github.com/playarchway/archway/compare/v0.1.1...v0.1.2) (2026-10-29)


### Bug Fixes

* **app:** load resources from Contents/Resources so release builds start ([77d1eeb](https://github.com/playarchway/archway/commit/77d1eeb746613631132889faab5a4f23230e4596))

## [0.1.1](https://github.com/playarchway/archway/compare/v0.1.0...v0.1.1) (2026-10-29)


### Bug Fixes

* **release:** offer Archway as a disk image to drag to Applications ([32bfb03](https://github.com/playarchway/archway/commit/32bfb03188194508e184b9207379f5edfd0e7f52))

## 0.1.0 (2026-10-28)


### ⚠ BREAKING CHANGES

* the bottle moves from bottles/steam-5228920 to bottles/steam, and install-game and launch-game require --app-id.

### Features

* add Overcross Steam proof of concept with D3DMetal backend ([974a09e](https://github.com/playarchway/archway/commit/974a09e652f0aeb7feb03db8c70fe63733b1c5ad))
* **app:** add ambient library background, amber accent, and hero transitions ([be82da6](https://github.com/playarchway/archway/commit/be82da6fd8bdd0299b88e3a6661b326d395fe2df))
* **app:** add SwiftUI library and game detail design ([db842da](https://github.com/playarchway/archway/commit/db842dad75a413ca8b76a122ee38c64cc3c9d79e))
* **app:** ask how a game ran after it closes ([2910e5b](https://github.com/playarchway/archway/commit/2910e5ba9f72bfc62d816b957925ddf88027f75a))
* **app:** close Windows Steam after the game when Archway started it ([d469cbc](https://github.com/playarchway/archway/commit/d469cbcd7b4e1227dcf468801d57d99333e4f0a0))
* **app:** fade the title bar frost in with the scroll ([95a0d90](https://github.com/playarchway/archway/commit/95a0d90970c885e78393cc6eda9b509b778a61bc))
* **app:** frost the title bar while content scrolls under it ([517a7d4](https://github.com/playarchway/archway/commit/517a7d4eff240595604dd2c8f6e7941185d22bd5))
* **app:** hide the Mac user name in exported logs ([19dbc1e](https://github.com/playarchway/archway/commit/19dbc1ef28a21f5106a1a31d1d93161fdb5e7ed6))
* **app:** install and start Steam games without Steam's window ([a2fc26d](https://github.com/playarchway/archway/commit/a2fc26d192b111dc932ed8203d7f00e3244b49d8))
* **app:** introduce Archway on first start ([6717c30](https://github.com/playarchway/archway/commit/6717c301b740fdd0c93cc33afbc6ffd0820b3ec7))
* **app:** launch alpha runtime games through the alpha bottle's Steam ([6e64507](https://github.com/playarchway/archway/commit/6e6450765e6c55f7f90970e803663ead49cc16b4))
* **app:** list open source licenses in a Settings tab ([6cdaf03](https://github.com/playarchway/archway/commit/6cdaf03fd65fd110b8188bb4df4b41359ccc7335))
* **app:** load the owned Steam library through a linked Steam session ([27b3ce5](https://github.com/playarchway/archway/commit/27b3ce5e6b3e76a084c8c7d0fe5e455e2ce5d747))
* **app:** rename the app to Archway, localize it, and offer the alpha runtime ([413a597](https://github.com/playarchway/archway/commit/413a5973710b3257f23d4ff4b4b87cf6417289ce))
* **app:** run every game on Archway's own Wine runtime ([236c013](https://github.com/playarchway/archway/commit/236c01395e484b6362ee2e20de982510d65a0e69))
* **app:** set up Archway in the background on first start ([b5c8661](https://github.com/playarchway/archway/commit/b5c8661ad4f1c239a154ad3eea97b61d252c1244))
* **app:** show Archway's storage and remove it with all its data ([aa583fb](https://github.com/playarchway/archway/commit/aa583fb6625d18ae58da9e09b225ed47b12a1e59))
* **app:** show how to use Archway in the introduction ([3f6b2cc](https://github.com/playarchway/archway/commit/3f6b2cc7077ab283a2a9fe7495e0faf9619b811b))
* **app:** show installed games instead of recently played ones ([b94df29](https://github.com/playarchway/archway/commit/b94df290270678d6b324a9445d084bb4574766ba))
* **app:** show licenses and the GPL notice in the About panel ([6299809](https://github.com/playarchway/archway/commit/62998091e33feac8bf288cff7986d473e4019a99))
* **app:** show Wine Mono's license list from the runtime ([c2f5b29](https://github.com/playarchway/archway/commit/c2f5b29233434db14b695bf44fb36c6791da6173))
* **app:** smoother backdrops and an animated game page header ([c8b273d](https://github.com/playarchway/archway/commit/c8b273d8f62ad588a63cf1aa3e17c34222ebad2c))
* **app:** start, watch, and install games from the library ([a1269ef](https://github.com/playarchway/archway/commit/a1269ef689cf799c03b1daf67522e6f818997128))
* **app:** take service addresses from the build environment ([309b6ac](https://github.com/playarchway/archway/commit/309b6acf933a62aa9541dd199e1208953ed03862))
* **app:** tell downloading and installing apart ([2826555](https://github.com/playarchway/archway/commit/2826555458d01b2085e06ad30d34a9af16246349))
* **app:** tell the introduction in scenes of glowing glass ([5e3d2db](https://github.com/playarchway/archway/commit/5e3d2dbf54c0ddaf05388b7f81c0eaa398505b32))
* **app:** uninstall Steam games from the game page ([940aec4](https://github.com/playarchway/archway/commit/940aec4b9218b837ed1d3186910545681cac379f))
* **app:** update Archway with Sparkle ([1b8f962](https://github.com/playarchway/archway/commit/1b8f96276449c37ce14ebc85a365c9c25489b686))
* **app:** update game stats after a session and when opening a game ([c4d24e0](https://github.com/playarchway/archway/commit/c4d24e02f015e4eb3a479852b6cf32845b110f96))
* **compatibility:** need three reports for a tested game and sum comparable setups ([c2799f5](https://github.com/playarchway/archway/commit/c2799f5f5e78f1b78d442974a270c2d481b70431))
* **runtime:** use the Wine runtime 11.20-e51c772 ([#2](https://github.com/playarchway/archway/issues/2)) ([a304bb8](https://github.com/playarchway/archway/commit/a304bb81ad57d3bc328cb54a161147451e47c536))
* **service:** add the compatibility report service ([c7d6065](https://github.com/playarchway/archway/commit/c7d60651026685717a163ff4188d56b9b7e9cc11))
* **setup:** switch to the bundled runtime after an update and remove old ones ([fa74b01](https://github.com/playarchway/archway/commit/fa74b0127f12796f84d5e13fa27da94fa920906d))
* **site:** add German pages ([01ab8a9](https://github.com/playarchway/archway/commit/01ab8a9859826c33f2639df75ca460b43a80680a))
* **site:** add the landing page ([7877c20](https://github.com/playarchway/archway/commit/7877c20ef61333a2d36548222eff68de11495cfb))
* **storage:** migrate legacy data to Archway ([fabd27e](https://github.com/playarchway/archway/commit/fabd27e35d9cc63994fb25e8d4e738209ee4dc89))


### Bug Fixes

* **app:** cross-fade the library backdrop from the previous artwork ([c05f62f](https://github.com/playarchway/archway/commit/c05f62f2b95ad40a5b38239765dd9e5eab076960))
* **app:** fill the window on the library's error page ([be37654](https://github.com/playarchway/archway/commit/be37654ff6fc6ea5c09d4494a6af7272c9e4b6e7))
* **app:** start the alpha bottle's Steam with the webhelper shim ([10c902f](https://github.com/playarchway/archway/commit/10c902fdae89ee3c7aef8273929061758057d9d9))
* **build:** bundle OvercrossCore's resources in Archway.app ([0cda4fe](https://github.com/playarchway/archway/commit/0cda4fe8167a1be8ffdd599302303201b1e0be44))
* **build:** compile the string catalog in build-app.sh ([9bae359](https://github.com/playarchway/archway/commit/9bae359bf84f60bfcf6c16db92d7dd57bb121aa3))
* **build:** find localizations in both resource bundle layouts ([eca198f](https://github.com/playarchway/archway/commit/eca198f40c71619c3ca7513538296afef9e97aa9))
* **core:** build Steam's launch arguments step by step ([f7a55b1](https://github.com/playarchway/archway/commit/f7a55b123f0b192f9ca3d63aabf84570cdcfd646))
* require macOS 15, which D3DMetal needs ([5ae8512](https://github.com/playarchway/archway/commit/5ae8512ff34ade8c091b67e56b635b3cd31dc668))


### Performance Improvements

* **app:** bound the artwork caches and share loads in flight ([c57d244](https://github.com/playarchway/archway/commit/c57d24471d3c8784ddfa342cf419ec9f989a8e75))
* **app:** keep disk work off the main thread ([1f5afed](https://github.com/playarchway/archway/commit/1f5afed143646187385b1cec6980e82729294229))
* **app:** sort the library once and drop the reveal mask after the bloom ([b15a99c](https://github.com/playarchway/archway/commit/b15a99c4aafaee515885b44c42437969712616e2))


### Reverts

* **app:** drop the title bar frost ([83ba953](https://github.com/playarchway/archway/commit/83ba953062217f81ad1f2a9a159ded6e88605145))


### Code Refactoring

* treat every game the same ([747dc0a](https://github.com/playarchway/archway/commit/747dc0a801a15d8f7cbd8e497d484e75fef9b88b))
