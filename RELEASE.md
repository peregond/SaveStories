# SaveMe Release

This project now has a separate direct-distribution pipeline for shipping a `.dmg` to other Apple Silicon Macs.

## What the release scripts do

- build the Swift release binary
- assemble `SaveMe.app`
- apply release bundle metadata
- optionally sign the app and dmg
- optionally notarize and staple both artifacts
- produce a user-friendly dmg with an `/Applications` shortcut

## Artifacts

- `dist/release/SaveMe.app`
- `dist/release/SaveMe.dmg`

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
export SAVESTORIES_BUNDLE_ID="com.example.savestories"
export SAVESTORIES_VERSION="0.2.0"
export SAVESTORIES_BUILD="14"
export SAVESTORIES_COPYRIGHT="Copyright © 2026 Your Name"
```

Build:

```bash
./scripts/build_release_dmg.sh
```

## Notarized release

First store your notary credentials once:

```bash
xcrun notarytool store-credentials "savestories-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then build with notarization:

```bash
export APPLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_NOTARY_PROFILE="savestories-notary"
./scripts/build_release_dmg.sh
```

## Runtime note

The `.dmg` distributes the native app bundle itself. On first launch the user can open Settings inside the app and press `Установить движок`, which prepares the local Playwright environment for that Mac.

That step still requires:

- `python3` available on the target machine
- internet access for `pip install playwright` and Chromium download
