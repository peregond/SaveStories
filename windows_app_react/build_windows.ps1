# Сборка Windows-клиента на React + Tauri.
# Результат: dist\windows-tauri\SaveMe-Windows\ (приложение + Node + node_worker) и, если установлен
# Inno Setup, установщик dist\windows-tauri\SaveMe-Windows-Setup-v<версия>.exe.
# Chromium в установщик не входит: приложение докачивает его при первом запуске.
param(
    [switch]$SkipInstaller
)
$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ui = $PSScriptRoot
$version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
$dist = Join-Path $root "dist\windows-tauri"
$appDir = Join-Path $dist "SaveMe-Windows"

foreach ($tool in "node", "npm", "cargo") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool не найден. Установи Node 24 LTS и Rust (stable)." }
}
python (Join-Path $root "scripts\check_version_consistency.py")
if ($LASTEXITCODE -ne 0) { throw "Версии в проекте не совпадают." }

if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force -Path $appDir | Out-Null

# 1. Интерфейс и exe
Push-Location $ui
npm ci
if ($LASTEXITCODE -ne 0) { throw "npm ci завершился с ошибкой." }
npm run tauri -- build --no-bundle
if ($LASTEXITCODE -ne 0) { throw "tauri build завершился с ошибкой." }
Pop-Location
$exe = Join-Path $ui "src-tauri\target\release\SaveMe-Windows.exe"
if (-not (Test-Path $exe)) { throw "Не найден $exe" }
Copy-Item $exe $appDir

# 2. Node runtime (тот же, что собирает проект)
$nodeDir = Join-Path $appDir "runtime\node"
New-Item -ItemType Directory -Force -Path $nodeDir | Out-Null
Copy-Item (Get-Command node).Source (Join-Path $nodeDir "node.exe")

# 3. node_worker без тестов и с production-зависимостями (Playwright)
$workerDst = Join-Path $appDir "node_worker"
robocopy (Join-Path $root "node_worker") $workerDst /E /XD node_modules test_fixtures /XF *.test.mjs | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy node_worker завершился с кодом $LASTEXITCODE" }
Push-Location $workerDst
npm ci --omit=dev
if ($LASTEXITCODE -ne 0) { throw "npm ci для node_worker завершился с ошибкой." }
Pop-Location
if (-not (Test-Path (Join-Path $workerDst "node_modules\playwright\cli.js"))) { throw "В node_worker нет playwright/cli.js." }

# 4. Установщик
if ($SkipInstaller) { Write-Host "Приложение собрано: $appDir"; exit 0 }
$iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if (-not $iscc) {
    $default = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if (Test-Path $default) { $iscc = @{ Source = $default } } else { throw "ISCC.exe не найден. Установи Inno Setup 6 или запусти с -SkipInstaller." }
}
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/p/?LinkId=2124703" -OutFile (Join-Path $appDir "MicrosoftEdgeWebview2Setup.exe")
$env:SAVESTORIES_VERSION = $version
& $iscc.Source "/DSourceDir=$appDir" "/DOutputDir=$dist" "/DOutputBaseFilename=SaveMe-Windows-Setup-v$version" (Join-Path $ui "SaveMe-Tauri.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC завершился с кодом $LASTEXITCODE" }
$setup = Join-Path $dist "SaveMe-Windows-Setup-v$version.exe"
if (-not (Test-Path $setup)) { throw "Установщик не создан: $setup" }
Write-Host "Готово: $setup"
