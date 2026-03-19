$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$workerDir = Join-Path $root "node_worker"
$appSupport = if ($env:DIMASAVE_APP_SUPPORT) { $env:DIMASAVE_APP_SUPPORT } else { Join-Path ($env:LOCALAPPDATA ?? $env:APPDATA) "DimaSave" }
$browsers = if ($env:DIMASAVE_PLAYWRIGHT_BROWSERS) { $env:DIMASAVE_PLAYWRIGHT_BROWSERS } else { Join-Path $appSupport "worker\\ms-playwright" }

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "node не найден. Установи Node 24 LTS."
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm не найден. Установи Node 24 LTS."
}

New-Item -ItemType Directory -Force -Path $browsers | Out-Null

Push-Location $workerDir
$env:PLAYWRIGHT_BROWSERS_PATH = $browsers
npm install
node .\node_modules\playwright\cli.js install chromium
Pop-Location

Write-Host ""
Write-Host "Node worker bootstrap complete."
Write-Host "Node: $((Get-Command node).Source)"
Write-Host "Worker: $workerDir\\bridge.mjs"
Write-Host "Playwright browsers: $browsers"
