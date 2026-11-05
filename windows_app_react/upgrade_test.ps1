# Проверка обновления на чистой Windows: ставит прежний релиз (WinUI), затем поверх него новый установщик
# и проверяет, что установленное приложение и воркер действительно работают.
# Запуск: ./windows_app_react/upgrade_test.ps1 -Setup <путь к новому установщику> [-PreviousTag v0.6.85]
param(
    [Parameter(Mandatory = $true)][string]$Setup,
    [string]$PreviousTag = "v0.6.85"
)
$ErrorActionPreference = "Stop"
$work = Join-Path ([System.IO.Path]::GetTempPath()) "saveme-upgrade-test"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$installDir = Join-Path $env:LOCALAPPDATA "Programs\SaveMeWindows"

function Install-Silent([string]$path, [string]$name) {
    $log = Join-Path $work "$name.log"
    $p = Start-Process -FilePath $path -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/LOG=$log" -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        if (Test-Path $log) { Get-Content $log -Tail 60 }
        throw "Установщик $name завершился с кодом $($p.ExitCode)"
    }
    Write-Host "OK: установлен $name"
}

function Assert-Path([string]$rel, [bool]$shouldExist = $true) {
    $full = Join-Path $installDir $rel
    if ((Test-Path $full) -ne $shouldExist) {
        Get-ChildItem $installDir -ErrorAction SilentlyContinue | Select-Object -First 40 | ForEach-Object { Write-Host "  $($_.Name)" }
        throw ("Ожидалось, что '{0}' {1}" -f $rel, $(if ($shouldExist) { "существует" } else { "отсутствует" }))
    }
}

# 1. Прежний релиз (WinUI-клиент), как у пользователей перед обновлением
$old = Join-Path $work "previous-setup.exe"
$url = "https://github.com/peregond/SaveStories/releases/download/$PreviousTag/SaveMe-Windows-Setup-$PreviousTag.exe"
Write-Host "Скачиваю прежний релиз: $url"
Invoke-WebRequest -Uri $url -OutFile $old
Install-Silent $old "previous"
Assert-Path "SaveMe.WinUI.exe"

# 2. Новый установщик поверх
Install-Silent $Setup "new"
Assert-Path "SaveMe-Windows.exe"
Assert-Path "unins000.exe"
Assert-Path "runtime\node\node.exe"
Assert-Path "node_worker\bridge.mjs"
Assert-Path "node_worker\node_modules\playwright\cli.js"
Assert-Path "SaveMe.WinUI.exe" $false

# 3. Воркер запускается из установленной папки встроенным Node
$env:SAVESTORIES_APP_SUPPORT = Join-Path $work "appdata"
$node = Join-Path $installDir "runtime\node\node.exe"
$bridge = Join-Path $installDir "node_worker\bridge.mjs"
$raw = '{"command":"environment"}' | & $node $bridge
$env_ = $raw | ConvertFrom-Json
if (-not $env_.ok) { throw "environment: $($env_.message)" }
Write-Host "OK: воркер отвечает — $($env_.message)"

# 4. Приложение запускается и не падает
$app = Start-Process -FilePath (Join-Path $installDir "SaveMe-Windows.exe") -PassThru
Start-Sleep -Seconds 15
if ($app.HasExited) { throw "Приложение завершилось через <15 с, код $($app.ExitCode)" }
Write-Host "OK: приложение работает (PID $($app.Id))"
Stop-Process -Id $app.Id -Force

# 5. Chromium и проверка сессии: сбой сети не должен блокировать выпуск, поэтому только предупреждение
try {
    $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $work "browsers"
    $env:SAVESTORIES_PLAYWRIGHT_BROWSERS = $env:PLAYWRIGHT_BROWSERS_PATH
    & $node (Join-Path $installDir "node_worker\node_modules\playwright\cli.js") install chromium
    if ($LASTEXITCODE -ne 0) { throw "install chromium: код $LASTEXITCODE" }
    $session = ('{"command":"check_session","headless":true}' | & $node $bridge) | ConvertFrom-Json
    Write-Host "check_session: status=$($session.status) message=$($session.message)"
    if ($session.status -notin @("session_missing", "session_ready")) { Write-Warning "Неожиданный статус check_session: $($session.status)" }
} catch {
    Write-Warning "Проверка Chromium пропущена: $($_.Exception.Message)"
}
Write-Host "Проверка обновления пройдена."
