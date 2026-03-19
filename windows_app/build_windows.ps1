$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$venv = Join-Path $PSScriptRoot ".venv"
$dist = Join-Path $root "dist\\windows"
$runtime = Join-Path $PSScriptRoot ".build\\runtime"
$runtimeBrowsers = Join-Path $runtime "ms-playwright"
$versionFile = Join-Path $root "VERSION"
$iconPath = Join-Path $root "packaging\\AppBundle\\DimaSave.ico"
$version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "0.1.39" }
$versionParts = $version.Split(".")
$major = if ($versionParts.Length -ge 1) { $versionParts[0] } else { "0" }
$minor = if ($versionParts.Length -ge 2) { $versionParts[1] } else { "0" }
$patch = if ($versionParts.Length -ge 3) { $versionParts[2] } else { "0" }
$versionInfoPath = Join-Path $PSScriptRoot ".build\\version_info.txt"

if (-not (Test-Path $venv)) {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        py -3 -m venv $venv
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        python -m venv $venv
    } else {
        throw "Python 3 не найден. Установи Python 3.13+."
    }
}

& "$venv\\Scripts\\python.exe" -m pip install --upgrade pip
& "$venv\\Scripts\\pip.exe" install -r (Join-Path $PSScriptRoot "requirements.txt")
& "$venv\\Scripts\\pip.exe" install playwright

New-Item -ItemType Directory -Force -Path $dist | Out-Null
New-Item -ItemType Directory -Force -Path $runtimeBrowsers | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $versionInfoPath) | Out-Null
$env:PLAYWRIGHT_BROWSERS_PATH = $runtimeBrowsers
& "$venv\\Scripts\\python.exe" -m playwright install chromium
& "$venv\\Scripts\\python.exe" (Join-Path $root "packaging\\generate_windows_icon.py") $iconPath

@"
VSVersionInfo(
  ffi=FixedFileInfo(
    filevers=($major, $minor, $patch, 0),
    prodvers=($major, $minor, $patch, 0),
    mask=0x3f,
    flags=0x0,
    OS=0x40004,
    fileType=0x1,
    subtype=0x0,
    date=(0, 0)
  ),
  kids=[
    StringFileInfo(
      [
        StringTable(
          u'040904B0',
          [
            StringStruct(u'CompanyName', u'DimaSave'),
            StringStruct(u'FileDescription', u'DimaSave for Windows'),
            StringStruct(u'FileVersion', u'$version'),
            StringStruct(u'InternalName', u'DimaSave-Windows'),
            StringStruct(u'OriginalFilename', u'DimaSave-Windows.exe'),
            StringStruct(u'ProductName', u'DimaSave'),
            StringStruct(u'ProductVersion', u'$version')
          ]
        )
      ]
    ),
    VarFileInfo([VarStruct(u'Translation', [1033, 1200])])
  ]
)
"@ | Set-Content -Path $versionInfoPath -Encoding UTF8

Push-Location $root

& "$venv\\Scripts\\pyinstaller.exe" `
    --noconfirm `
    --windowed `
    --name DimaSave-Windows `
    --distpath $dist `
    --workpath (Join-Path $dist "build") `
    --specpath $dist `
    --icon $iconPath `
    --version-file $versionInfoPath `
    --collect-all playwright `
    --hidden-import playwright.sync_api `
    --add-data "$root\\Sources\\DimaSave\\Resources\\worker;worker" `
    --add-data "$root\\VERSION;." `
    --add-data "$runtimeBrowsers;runtime\\ms-playwright" `
    --add-data "$PSScriptRoot\\bootstrap_worker.ps1;windows_app" `
    "$PSScriptRoot\\dimasave_windows\\main.py"

Pop-Location
