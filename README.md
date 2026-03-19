# DimaSave

Desktop utility for downloading Instagram stories through a local browser automation worker.

## Stack

- `SwiftUI` macOS shell built with Swift Package Manager
- local Python worker
- `Playwright` with persistent Chromium profile
- separate Windows shell under [windows_app/README.md](/Users/peregon/Documents/DimaSave/windows_app/README.md)

## Current MVP

- choose a save directory
- prepare or verify the worker environment from inside the app
- open a visible Instagram login browser
- check whether the saved session is still valid
- download active stories from a profile URL or username
- write a JSON manifest for each downloaded media item

## Bootstrap

The worker expects a local virtual environment in:

`~/Library/Application Support/DimaSave/worker/.venv`

Install it manually with:

```bash
./scripts/bootstrap_worker.sh
```

This creates the venv, installs `playwright`, and downloads Chromium into the app support folder.

The app can do the same from Settings via `Установить движок`, which is the intended path for `.dmg` installs on other Macs.

Release builds now prefer a bundled runtime when available:

- embedded `Python.framework`
- embedded `site-packages` for Playwright
- embedded Chromium and ffmpeg under `Contents/SharedSupport/runtime`

## Run

```bash
./scripts/run_app.sh
```

Or directly:

```bash
swift run DimaSave
```

## Windows Prototype

There is now a separate Windows client scaffold in:

[windows_app/README.md](/Users/peregon/Documents/DimaSave/windows_app/README.md)

It reuses the same Python worker and supports:

- visible Instagram login
- session check
- single profile download
- batch queue download

Current limitation:

- the Windows build still expects `Python 3.13+` on the target machine
- a fully self-contained Windows release is a separate next step

## Notes

- The worker keeps a persistent browser profile under `~/Library/Application Support/DimaSave/worker/browser-profile`.
- Each saved media item gets a manifest in `.../manifests/` with source URL, viewer page URL, type, timestamp, and sha256.
- The automation is intentionally visible and conservative. It does not try to bypass login checks or anti-bot challenges.
- The worker now prefers a metadata-first path: it captures Instagram JSON responses, resolves story items and media variants, and only falls back to DOM heuristics if metadata extraction fails.

## Release Packaging

Unsigned direct-distribution build:

```bash
./scripts/build_release_dmg.sh
```

Signed and notarized build:

```bash
export APPLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_NOTARY_PROFILE="dimasave-notary"
export DIMASAVE_BUNDLE_ID="com.example.dimasave"
export DIMASAVE_VERSION="0.2.0"
export DIMASAVE_BUILD="14"
./scripts/build_release_dmg.sh
```

The release artifact is written to `dist/release/DimaSave.dmg`.
