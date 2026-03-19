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

## Runtime notes

This Windows app is packaged with PyInstaller and includes the runtime payload (`playwright` + Chromium) in the distribution folder.

From source, local development still assumes:

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

Main executable:

```text
dist/windows/DimaSave-Windows/DimaSave-Windows.exe
```

Optional packaged archive (for sharing):

```text
dist/windows/DimaSave-Windows.zip
```

Create ZIP + SHA256 checksum:

```powershell
cd windows_app
./package_windows_artifact.ps1
```

## Build `.exe` from macOS through GitHub Actions

If the project is pushed to GitHub, there is also a Windows workflow:

[windows-exe.yml](../.github/workflows/windows-exe.yml)

After a manual run or a push that touches the Windows files, the workflow uploads:

```text
DimaSave-Windows
```

as a downloadable artifact.

The artifact contains:

- `DimaSave-Windows/` (full runnable folder)
- `DimaSave-Windows.zip` (portable archive)
- `DimaSave-Windows.sha256` (checksum for zip)

## Next step

- polish installer UX (MSI/Inno Setup)
- validate final artifact behavior on multiple Windows versions
