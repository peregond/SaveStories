$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$distRoot = Join-Path $root "dist\\windows"
$appDir = Join-Path $distRoot "SaveStories-Windows"
$versionFile = Join-Path $root "VERSION"
$version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "0.4.1" }
$outputFileName = "SaveStories-Windows-Setup-v$version"
$issPath = Join-Path $PSScriptRoot "SaveStories-Windows.iss"
$iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue

if (-not (Test-Path $appDir)) {
    throw "Build folder not found: $appDir. Run build_windows.ps1 first."
}

if (-not (Test-Path (Join-Path $appDir "SaveStories-Windows.exe"))) {
    throw "Main executable not found in: $appDir"
}

if (-not (Test-Path $issPath)) {
    throw "Inno Setup script not found: $issPath"
}

if (-not $iscc) {
    $defaultIscc = "C:\\Program Files (x86)\\Inno Setup 6\\ISCC.exe"
    if (Test-Path $defaultIscc) {
        $iscc = @{ Source = $defaultIscc }
    } else {
        throw "ISCC.exe not found. Install Inno Setup 6 first."
    }
}

New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

& $iscc.Source `
    "/DSourceDir=$appDir" `
    "/DOutputDir=$distRoot" `
    "/DOutputBaseFilename=$outputFileName" `
    $issPath

$setupPath = Join-Path $distRoot "$outputFileName.exe"
if (-not (Test-Path $setupPath)) {
    throw "Installer output was not created: $setupPath"
}

Write-Host "Built installer:"
Write-Host " - $setupPath"
