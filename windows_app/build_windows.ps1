$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$venv = Join-Path $PSScriptRoot ".venv"
$dist = Join-Path $root "dist\\windows"
$runtime = Join-Path $PSScriptRoot ".build\\runtime"
$runtimeBrowsers = Join-Path $runtime "ms-playwright"

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
$env:PLAYWRIGHT_BROWSERS_PATH = $runtimeBrowsers
& "$venv\\Scripts\\python.exe" -m playwright install chromium

Push-Location $root

& "$venv\\Scripts\\pyinstaller.exe" `
    --noconfirm `
    --windowed `
    --name DimaSave-Windows `
    --distpath $dist `
    --workpath (Join-Path $dist "build") `
    --specpath $dist `
    --collect-all playwright `
    --hidden-import playwright.sync_api `
    --add-data "$root\\Sources\\DimaSave\\Resources\\worker;worker" `
    --add-data "$runtimeBrowsers;runtime\\ms-playwright" `
    --add-data "$PSScriptRoot\\bootstrap_worker.ps1;windows_app" `
    "$PSScriptRoot\\dimasave_windows\\main.py"

Pop-Location
