$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$venv = Join-Path $PSScriptRoot ".venv"
$dist = Join-Path $root "dist\\windows"
$runtime = Join-Path $PSScriptRoot ".build\\runtime"
$runtimeBrowsers = Join-Path $runtime "ms-playwright"
$runtimeNode = Join-Path $runtime "node"
$versionFile = Join-Path $root "VERSION"
$iconPath = Join-Path $root "packaging\\AppBundle\\DimaSave.ico"
$version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "0.3.2" }
$nodeWorkerDir = Join-Path $root "node_worker"
$versionParts = $version.Split(".")
$major = if ($versionParts.Length -ge 1) { $versionParts[0] } else { "0" }
$minor = if ($versionParts.Length -ge 2) { $versionParts[1] } else { "0" }
$patch = if ($versionParts.Length -ge 3) { $versionParts[2] } else { "0" }
$versionInfoPath = Join-Path $PSScriptRoot ".build\\version_info.txt"
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
$npmCommand = Get-Command npm -ErrorAction SilentlyContinue

if (-not $nodeCommand) {
    throw "Node 24 LTS не найден. Установи Node 24 LTS."
}

if (-not $npmCommand) {
    throw "npm не найден. Установи Node 24 LTS."
}

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

New-Item -ItemType Directory -Force -Path $dist | Out-Null
New-Item -ItemType Directory -Force -Path $runtimeBrowsers | Out-Null
New-Item -ItemType Directory -Force -Path $runtimeNode | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $versionInfoPath) | Out-Null
$env:PLAYWRIGHT_BROWSERS_PATH = $runtimeBrowsers
& "$venv\\Scripts\\python.exe" (Join-Path $root "packaging\\generate_windows_icon.py") $iconPath

Push-Location $nodeWorkerDir
npm install
node .\node_modules\playwright\cli.js install chromium
Pop-Location

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
            StringStruct(u'CompanyName', u'SaveStories'),
            StringStruct(u'FileDescription', u'SaveStories for Windows'),
            StringStruct(u'FileVersion', u'$version'),
            StringStruct(u'InternalName', u'SaveStories-Windows'),
            StringStruct(u'OriginalFilename', u'SaveStories-Windows.exe'),
            StringStruct(u'ProductName', u'SaveStories'),
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
    --name SaveStories-Windows `
    --distpath $dist `
    --workpath (Join-Path $dist "build") `
    --specpath $dist `
    --icon $iconPath `
    --version-file $versionInfoPath `
    --add-binary "$($nodeCommand.Source);runtime\\node" `
    --add-data "$root\\node_worker;node_worker" `
    --add-data "$root\\Sources\\DimaSave\\Resources\\update_config.json;." `
    --add-data "$root\\VERSION;." `
    --add-data "$runtimeBrowsers;runtime\\ms-playwright" `
    --add-data "$PSScriptRoot\\bootstrap_node_worker.ps1;windows_app" `
    "$PSScriptRoot\\dimasave_windows\\main.py"

Pop-Location
