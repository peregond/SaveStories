# DimaSave Release

This project now has a separate direct-distribution pipeline for shipping a `.dmg` to other Apple Silicon Macs.

## What the release scripts do

- build the Swift release binary
- assemble `DimaSave.app`
- apply release bundle metadata
- optionally sign the app and dmg
- optionally notarize and staple both artifacts
- produce a user-friendly dmg with an `/Applications` shortcut

## Artifacts

- `dist/release/DimaSave.app`
- `dist/release/DimaSave.dmg`

## Unsigned local release

```bash
./scripts/build_release_dmg.sh
```

This is enough for private testing, but macOS will warn that the app is unsigned.

## Signed release

Set your Apple Developer identity:

```bash
export APPLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

Optional metadata overrides:

```bash
export DIMASAVE_BUNDLE_ID="com.example.dimasave"
export DIMASAVE_VERSION="0.2.0"
export DIMASAVE_BUILD="14"
export DIMASAVE_COPYRIGHT="Copyright © 2026 Your Name"
```

Build:

```bash
./scripts/build_release_dmg.sh
```

## Notarized release

First store your notary credentials once:

```bash
xcrun notarytool store-credentials "dimasave-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then build with notarization:

```bash
export APPLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_NOTARY_PROFILE="dimasave-notary"
./scripts/build_release_dmg.sh
```

## Runtime note

The `.dmg` distributes the native app bundle itself. On first launch the user can open Settings inside the app and press `Установить движок`, which prepares the local Playwright environment for that Mac.

That step still requires:

- `python3` available on the target machine
- internet access for `pip install playwright` and Chromium download
