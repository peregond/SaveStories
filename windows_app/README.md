# DimaSave for Windows

This folder contains the first Windows shell for DimaSave.

## Current status

- separate Windows desktop UI on `PySide6`
- reuses the same downloader core from `Sources/DimaSave/Resources/worker/bridge.py`
- supports:
  - visible Instagram login
  - session check
  - single profile download
  - batch queue download
  - stop current batch item

## Important limitation

This first Windows version is not yet a fully self-contained installer like the current macOS `.dmg`.

Right now it assumes:

- `Python 3.13+` is installed on the target Windows machine
- the worker environment is prepared through `bootstrap_worker.ps1`

## Run from source

```powershell
cd windows_app
./run_windows.ps1
```

## Prepare worker runtime

```powershell
cd windows_app
./bootstrap_worker.ps1
```

This creates:

- `%LOCALAPPDATA%\DimaSave\worker\.venv`
- `%LOCALAPPDATA%\DimaSave\worker\ms-playwright`

## Build `.exe`

```powershell
cd windows_app
./build_windows.ps1
```

Artifacts go to:

```text
dist/windows/DimaSave-Windows/
```

## Build `.exe` from macOS through GitHub Actions

If the project is pushed to GitHub, there is also a Windows workflow:

[windows-exe.yml](/Users/peregon/Documents/DimaSave/.github/workflows/windows-exe.yml)

After a manual run or a push that touches the Windows files, the workflow uploads:

```text
DimaSave-Windows
```

as a downloadable artifact.

## Next step

The next packaging step for Windows is to ship a bundled Python runtime, so the `.exe` does not depend on a user-installed Python.

Update:

- the current Windows build now bundles the app runtime through `PyInstaller`
- it also bundles `playwright` and a Chromium payload into the Windows distribution
- the remaining work is polishing the installer and validating the final Windows artifact on a real Windows machine
