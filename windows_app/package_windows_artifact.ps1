$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$distRoot = Join-Path $root "dist\\windows"
$appDir = Join-Path $distRoot "DimaSave-Windows"
$zipPath = Join-Path $distRoot "DimaSave-Windows.zip"
$shaPath = Join-Path $distRoot "DimaSave-Windows.sha256"
$exePath = Join-Path $appDir "DimaSave-Windows.exe"

if (-not (Test-Path $appDir)) {
    throw "Build folder not found: $appDir. Run build_windows.ps1 first."
}

if (-not (Test-Path $exePath)) {
    throw "Main executable not found: $exePath."
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Compress-Archive -Path "$appDir/*" -DestinationPath $zipPath

$hash = Get-FileHash -Algorithm SHA256 $zipPath
"{0}  {1}" -f $hash.Hash.ToLower(), (Split-Path -Leaf $hash.Path) | Set-Content -Encoding UTF8 $shaPath

Write-Host "Packaged artifact:"
Write-Host " - $appDir"
Write-Host " - $zipPath"
Write-Host " - $shaPath"
