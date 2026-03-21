$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$distRoot = Join-Path $root "dist\\windows"
$appDir = Join-Path $distRoot "SaveStories-Windows"
$zipPath = Join-Path $distRoot "SaveStories-Windows.zip"
$shaPath = Join-Path $distRoot "SaveStories-Windows.sha256"
$exePath = Join-Path $appDir "SaveStories-Windows.exe"
$versionFile = Join-Path $root "VERSION"
$version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "0.4.1" }
$setupPath = Join-Path $distRoot "SaveStories-Windows-Setup-v$version.exe"
$setupShaPath = Join-Path $distRoot "SaveStories-Windows-Setup-v$version.sha256"

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

if (Test-Path $setupPath) {
    $setupHash = Get-FileHash -Algorithm SHA256 $setupPath
    "{0}  {1}" -f $setupHash.Hash.ToLower(), (Split-Path -Leaf $setupHash.Path) | Set-Content -Encoding UTF8 $setupShaPath
}

Write-Host "Packaged artifact:"
Write-Host " - $appDir"
Write-Host " - $zipPath"
Write-Host " - $shaPath"
if (Test-Path $setupPath) {
    Write-Host " - $setupPath"
    Write-Host " - $setupShaPath"
}
