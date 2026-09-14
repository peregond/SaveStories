# Preparing a macOS release

The app continues to support macOS 14 and newer. The minimum OS and SDK recorded
in the packaged Info.plist are derived from the app and media helper Mach-O load
commands. Selecting a newer SDK does not raise the minimum supported OS.

## Local preview

```sh
./scripts/build_beta_app.sh
python3 scripts/macos_bundle.py verify --app beta-build/release/SaveMe.app
```

The preview has the bundle identifier `local.saveme.macos27.preview`, display name
`SaveMe Preview`, an ad-hoc signature, and disabled Sparkle updates. Its bundle ID
can be overridden with `SAVESTORIES_BUNDLE_ID`. App resources and frameworks come
from the current release output directory, including when a debug build already
exists. Missing runtime sources or media helpers fail packaging.

## macOS 27 validation

Select an installed Xcode containing the macOS 27 SDK with `DEVELOPER_DIR`, then:

```sh
SAVEME_REQUIRE_SDK=27 ./scripts/build_beta_app.sh
python3 scripts/macos_bundle.py verify --app beta-build/release/SaveMe.app --require-sdk 27
```

This explicitly rejects an older SDK or a bundle without a native arm64 app.
Without `SAVEME_REQUIRE_SDK`, local builds work with the available SDK and report
its actual version. A successful build on an older OS does not establish macOS 27
runtime compatibility.

On macOS 27, exercise onboarding, authentication, one-profile and batch downloads,
cancellation, media muxing, choosing an output folder, restart, light/dark
appearance, Reduce Transparency, Reduce Motion, and keyboard navigation. Repeat
the core flows on macOS 14 to verify the retained deployment target. A new SDK or
macOS beta may require repeating these checks.

## Distribution

`build_release_dmg.sh` uses `APPLE_SIGN_IDENTITY` and `APPLE_NOTARY_PROFILE` when
provided. No signing credentials are bundled in the repository. After signing and
notarization, verify the app before publishing:

```sh
python3 scripts/macos_bundle.py verify --app dist/release/SaveMe.app --require-sdk 27 --distribution
```

This verifies the bundle seal, required resources, architecture coverage, binary
SDK and minimum OS, Developer ID Application signature, hardened runtime, and
stapled notarization ticket. Publishing remains a separate action. These checks
do not substitute for testing a quarantined download on a clean Mac.

Apple references: [macOS release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes),
[notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
