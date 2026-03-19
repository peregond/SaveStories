$ErrorActionPreference = "Stop"

$appSupport = if ($env:DIMASAVE_APP_SUPPORT) {
    $env:DIMASAVE_APP_SUPPORT
} elseif ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA "DimaSave"
} elseif ($env:APPDATA) {
    Join-Path $env:APPDATA "DimaSave"
} else {
    Join-Path (Get-Location) ".runtime\\DimaSave"
}

$workerRoot = Join-Path $appSupport "worker"
$venv = Join-Path $workerRoot ".venv"
$browsers = Join-Path $workerRoot "ms-playwright"

New-Item -ItemType Directory -Force -Path $workerRoot | Out-Null

if (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 -m venv $venv
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    python -m venv $venv
} else {
    throw "Python 3 не найден. Установи Python 3.13+ и повтори настройку движка."
}

& "$venv\\Scripts\\python.exe" -m pip install --upgrade pip setuptools wheel
& "$venv\\Scripts\\pip.exe" install playwright

$env:PLAYWRIGHT_BROWSERS_PATH = $browsers
& "$venv\\Scripts\\python.exe" -m playwright install chromium

Write-Host ""
Write-Host "Worker bootstrap complete."
Write-Host "Python: $venv\\Scripts\\python.exe"
Write-Host "Browser profile: $workerRoot\\browser-profile"
Write-Host "Playwright browsers: $browsers"
