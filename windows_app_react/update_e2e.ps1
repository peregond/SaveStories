# Проверка всего пути обновления изнутри приложения на Windows: установленное приложение находит «новую» версию на локальном
# сервере релизов, скачивает установщик (SHA-256 + подпись), запускает его без повышения прав, закрывается;
# установщик в тихом режиме ставит файлы и запускает приложение снова.
# Запуск: ./windows_app_react/update_e2e.ps1 -Setup dist\windows-tauri\SaveMe-Windows-Setup-vX.exe [-OutDir update-e2e]
param(
    [Parameter(Mandatory = $true)][string]$Setup,
    [string]$OutDir = "update-e2e"
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$Setup = (Resolve-Path $Setup).Path
$installDir = Join-Path $env:LOCALAPPDATA "Programs\SaveMeWindows"
$exe = Join-Path $installDir "SaveMe-Windows.exe"
$data = Join-Path $OutDir "appdata"
$node = (Get-Command node).Source   # node из PATH: каталог установки при обновлении очищается
$here = $PSScriptRoot
$failed = New-Object System.Collections.Generic.List[string]
function Fail([string]$m) { Write-Host "FAIL $m"; $failed.Add($m) }
function Ok([string]$m) { Write-Host "OK   $m" }

# 1. Чистая установка проверяемого установщика
$p = Start-Process -FilePath $Setup -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/LOG=$OutDir\setup-first.log" -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Установщик завершился с кодом $($p.ExitCode)" }
if (-not (Test-Path $exe)) { throw "Нет $exe" }
Ok "установлено"
$playwright = Join-Path $installDir "node_worker\node_modules\playwright\index.mjs"
# Драйвер браузера копируем из установки: при обновлении каталог установки очищается, а он нужен и после него.
$pwCopy = Join-Path $OutDir "playwright-copy"
Copy-Item -Recurse -Force (Join-Path $installDir "node_worker\node_modules\playwright") (Join-Path $pwCopy "playwright\node_modules\playwright") -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force (Join-Path $installDir "node_worker\node_modules\playwright-core") (Join-Path $pwCopy "playwright\node_modules\playwright-core") -ErrorAction SilentlyContinue
$playwrightStable = Join-Path $pwCopy "playwright\node_modules\playwright\index.mjs"
if (-not (Test-Path $playwrightStable)) { $playwrightStable = $playwright }

# 2. Локальный «GitHub Releases»
$portFile = Join-Path $OutDir "server.port"
Remove-Item $portFile -ErrorAction SilentlyContinue
$server = Start-Process -FilePath $node -ArgumentList @((Join-Path $here "update_e2e_server.mjs"), "--setup=$Setup", "--portfile=$portFile") -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutDir "server.log")
for ($i = 0; $i -lt 30 -and -not (Test-Path $portFile); $i++) { Start-Sleep -Seconds 1 }
if (-not (Test-Path $portFile)) { throw "Сервер релизов не запустился" }
$port = (Get-Content $portFile -Raw).Trim()
Ok "сервер релизов на порту $port"

# 3. Приложение с отладочным портом и адресом обновлений на локальный сервер
$env:SAVESTORIES_APP_SUPPORT = $data
$env:SAVEME_CDP_PORT = "9222"
$env:SAVEME_UPDATE_API = "http://127.0.0.1:$port/releases/latest"
$old = Start-Process -FilePath $exe -PassThru
$oldPid = $old.Id
try {
    & $node (Join-Path $here "update_e2e.mjs") "--playwright=$playwrightStable" "--out=$OutDir" "--phase=update"
    if ($LASTEXITCODE -ne 0) { Fail "сценарий обновления (проверка → скачивание → запуск установщика) не прошёл" }
    else { Ok "обновление скачано и установщик запущен" }

    # 4. Старое приложение закрылось само
    $closed = $false
    for ($i = 0; $i -lt 60; $i++) { if (-not (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) { $closed = $true; break }; Start-Sleep -Seconds 1 }
    if ($closed) { Ok "приложение закрылось само" } else { Fail "приложение не закрылось за 60 с" }

    # 5. Установщик отработал, новое приложение запущено (другой PID)
    $new = $null
    for ($i = 0; $i -lt 180; $i++) {
        $new = Get-Process -Name "SaveMe-Windows" -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $oldPid } | Select-Object -First 1
        if ($new) { break }
        Start-Sleep -Seconds 1
    }
    if ($new) { Ok "после обновления приложение запущено снова (PID $oldPid -> $($new.Id))" } else { Fail "после обновления приложение не запустилось за 180 с" }

    $log = Get-ChildItem -Path $data -Recurse -Filter "installer.log" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($log) {
        Copy-Item $log.FullName (Join-Path $OutDir "installer.log") -Force
        $text = Get-Content $log.FullName -Raw
        if ($text -match "Installation process succeeded") { Ok "лог установщика: успех" } else { Fail "в логе установщика нет «Installation process succeeded»" }
        if ($text -match "Running in silent mode|Silent") { Ok "установщик шёл в тихом режиме" }
        if ($text -match "Elevated|elevat") { Write-Host "NOTE лог упоминает повышение прав: $($Matches[0])" }
    } else { Fail "лог установщика не найден" }
    if (Test-Path (Join-Path $installDir "unins000.exe")) { Ok "unins000.exe на месте" } else { Fail "после обновления нет unins000.exe" }

    # 6. Интерфейс нового приложения загрузился
    if ($new) {
        & $node (Join-Path $here "update_e2e.mjs") "--playwright=$playwrightStable" "--out=$OutDir" "--phase=after"
        if ($LASTEXITCODE -eq 0) { Ok "интерфейс обновлённого приложения открылся" } else { Fail "интерфейс обновлённого приложения не открылся" }
    }
} finally {
    Get-Process -Name "SaveMe-Windows" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name msedgewebview2 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if ($server) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:\SAVEME_CDP_PORT, Env:\SAVEME_UPDATE_API -ErrorAction SilentlyContinue
}
if ($failed.Count -gt 0) { throw "Проверка обновления не прошла: " + ($failed -join "; ") }
Write-Host "Проверка обновления изнутри приложения пройдена."
