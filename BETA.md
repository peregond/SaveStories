# Beta Build Notes

Current beta version: `0.1.12-beta (13)`

## Goal

Produce a native `.app` bundle for Apple Silicon macOS without App Store distribution.

## Build

```bash
./scripts/bootstrap_worker.sh
./scripts/build_beta_app.sh
```

Expected output:

```text
beta-build/release/DimaSave.app
```

## What The App Needs On First Run

- a writable app runtime directory
- the local Playwright worker venv
- Chromium downloaded by `bootstrap_worker.sh`
- manual Instagram login in the visible browser window

## Current Blocker In This Environment

The source is ready for a beta build, but this machine currently does not have a matching Apple Swift toolchain + macOS SDK pair for compiling the SwiftUI shell.

Observed issue:

- active tools come from `CommandLineTools`
- no full `Xcode.app` is installed
- current SDK and `swift` compiler versions do not match

Once a matching Xcode/SDK is selected locally, `build_beta_app.sh` should be the path to a native beta bundle.
