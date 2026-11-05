# Contributing to SeasonMyMac

Thanks for wanting to help! Bug fixes, polish, performance work and new seasons are all welcome.

## Getting started

1. Fork and clone the repository.
2. Open `SeasonMyMac.xcodeproj` in Xcode 27 or later and press **⌘R**. (The app itself runs on macOS 14 and later.)
3. Run the simulation tests:

   ```sh
   cd Packages/SeasonKit
   swift test
   ```

No Apple developer team is needed to build. See "Signing" in the [README](README.md) if you want to use yours.

## Before you open a pull request

- `swift test` passes in `Packages/SeasonKit`.
- `swift format lint -r SeasonMyMac Packages/SeasonKit scripts` reports nothing. Run `swift format -i -r …` to fix formatting automatically.
- The app builds without warnings.
- For anything that runs every frame, check CPU in Activity Monitor with a **Release** build. Snow plus lights should stay at a few percent of one core.
- For visual changes, include a screenshot or a short recording.

For bigger changes, open an issue first so we can agree on the approach.

## Code style

- Swift 6 language mode. The app target defaults to main-actor isolation.
- Keep simulation code in `SeasonKit`: plain value types, no AppKit or Metal, with unit tests.
- Name things for what they are, and add a doc comment explaining *why* whenever the code alone doesn't make it obvious.
- Nothing allocated per frame on the hot path. Reuse buffers.

## Adding a season

Seasons are the most fun thing to build. Roughly:

1. **Simulation.** Add the season's world to `Packages/SeasonKit` next to `SnowWorld` and `LightString`: a value type with a `step(dt:…)` method, plus tests.
2. **Season.** Make `isAvailable` return `true` for it in `Season.swift`, and give it a title, tagline and colour in `Season+UI.swift`.
3. **Rendering.** Add instance types to `ShaderTypes.swift`, shaders to `Scene.metal`, and a draw call in `SceneRenderer`.
4. **Wiring.** Step and draw it from `SeasonView` when the season is selected.
5. **Settings.** Add its options to `AppSettings`. New fields get their defaults automatically, so no one's saved settings break. Then add a pane to `SettingsView`.

Have an idea but not the time? [Pitch a season](../../issues/new?template=season_idea.yml).

## Making a release

Releases are made by the maintainer from a Mac with the signing certificate:

1. Bump `MARKETING_VERSION` in the Xcode project (Target → General → Version).
2. Add a `## [x.y.z] - date` section to `CHANGELOG.md`, and commit.
3. Run `./scripts/release.sh`. It builds the app, packs it into `SeasonMyMac.dmg`, has Apple notarize it, tags the commit and publishes a GitHub release. `install.sh` always installs the newest release.

Notarizing needs a Developer ID certificate and a one-time `xcrun notarytool store-credentials seasonmymac-notary`. Without them, run `./scripts/release.sh --without-notarizing`. It signs with the best certificate you have, and `install.sh` still opens the app without a warning.

To only make the disk image, run `./scripts/make-dmg.sh` (add `--notarize` for a notarized one).

## Reporting bugs

Use the [bug report form](../../issues/new?template=bug_report.yml). Your macOS version and display setup help a lot.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By taking part, you agree to uphold it.
