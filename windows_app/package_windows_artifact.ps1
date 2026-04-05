$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$distRoot = Join-Path $root "dist\\windows"
$appDir = Join-Path $distRoot "SaveStories-Windows"
$zipPath = Join-Path $distRoot "SaveStories-Windows.zip"
$sevenZipPath = Join-Path $distRoot "SaveStories-Windows.7z"
$shaPath = Join-Path $distRoot "SaveStories-Windows.sha256"
$exePath = Join-Path $appDir "SaveStories-Windows.exe"
$versionFile = Join-Path $root "VERSION"
$version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "0.5.1" }
$setupPath = Join-Path $distRoot "SaveStories-Windows-Setup-v$version.exe"
$setupShaPath = Join-Path $distRoot "SaveStories-Windows-Setup-v$version.sha256"
$sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue

if (-not (Test-Path $appDir)) {
    throw "Build folder not found: $appDir. Run build_windows.ps1 first."
}

if (-not (Test-Path $exePath)) {
    throw "Main executable not found: $exePath."
}

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

if (Test-Path $sevenZipPath) {
    Remove-Item $sevenZipPath -Force
}

Compress-Archive -Path "$appDir/*" -DestinationPath $zipPath

if ($sevenZip) {
    & $sevenZip.Source a -t7z -mx=9 -m0=lzma2 -mmt=on $sevenZipPath "$appDir\\*" | Out-Null
    $hashTarget = $sevenZipPath
} else {
    $hashTarget = $zipPath
}

$hash = Get-FileHash -Algorithm SHA256 $hashTarget
"{0}  {1}" -f $hash.Hash.ToLower(), (Split-Path -Leaf $hash.Path) | Set-Content -Encoding UTF8 $shaPath

if (Test-Path $setupPath) {
    $setupHash = Get-FileHash -Algorithm SHA256 $setupPath
    "{0}  {1}" -f $setupHash.Hash.ToLower(), (Split-Path -Leaf $setupHash.Path) | Set-Content -Encoding UTF8 $setupShaPath
}

Write-Host "Packaged artifact:"
Write-Host " - $appDir"
Write-Host " - $zipPath"
if (Test-Path $sevenZipPath) {
    Write-Host " - $sevenZipPath"
}
Write-Host " - $shaPath"
if (Test-Path $setupPath) {
    Write-Host " - $setupPath"
    Write-Host " - $setupShaPath"
}
