# Проверка установленного приложения на Windows: скриншоты, сценарий в интерфейсе через CDP,
# перезапуск (очередь должна восстановиться), измерение памяти и процессора; для сравнения — прежний WinUI-клиент.
# Запуск: ./windows_app_react/ci_inspect.ps1 -OutDir inspect [-CompareWinUITag v0.6.85]
param(
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$CompareWinUITag = ""
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$installDir = Join-Path $env:LOCALAPPDATA "Programs\SaveMeWindows"
$exe = Join-Path $installDir "SaveMe-Windows.exe"
$node = Join-Path $installDir "runtime\node\node.exe"
$playwright = Join-Path $installDir "node_worker\node_modules\playwright\index.mjs"
$script = Join-Path $PSScriptRoot "ci_inspect.mjs"
$data = Join-Path $OutDir "appdata"
$report = New-Object System.Collections.Generic.List[string]
foreach ($p in @($exe, $node, $playwright)) { if (-not (Test-Path $p)) { throw "Не найдено: $p" } }

function Get-Tree([int]$rootPid) {
    $all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId
    $ids = New-Object System.Collections.Generic.List[int]; $ids.Add($rootPid)
    do {
        $new = @($all | Where-Object { $ids.Contains([int]$_.ParentProcessId) -and -not $ids.Contains([int]$_.ProcessId) } | ForEach-Object { [int]$_.ProcessId })
        foreach ($n in $new) { $ids.Add($n) }
    } while ($new.Count -gt 0)
    return $ids
}

function Measure-App([int]$rootPid, [int]$seconds) {
    $ids = Get-Tree $rootPid
    $before = @(Get-Process -Id $ids -ErrorAction SilentlyContinue)
    $cpu0 = ($before | ForEach-Object { $_.TotalProcessorTime.TotalSeconds } | Measure-Object -Sum).Sum
    Start-Sleep -Seconds $seconds
    $ids = Get-Tree $rootPid
    $after = @(Get-Process -Id $ids -ErrorAction SilentlyContinue)
    $cpu1 = ($after | ForEach-Object { $_.TotalProcessorTime.TotalSeconds } | Measure-Object -Sum).Sum
    [pscustomobject]@{
        Processes   = $after.Count
        WorkingSetMB = [math]::Round((($after | Measure-Object WorkingSet64 -Sum).Sum) / 1MB, 1)
        PrivateMB    = [math]::Round((($after | Measure-Object PrivateMemorySize64 -Sum).Sum) / 1MB, 1)
        CpuPercentOfOneCore = [math]::Round(($cpu1 - $cpu0) / $seconds * 100, 1)
    }
}

function Save-DesktopScreenshot([string]$name) {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $path = Join-Path $OutDir "$name.png"
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Write-Host "Снимок рабочего стола: $path ($($b.Width)x$($b.Height))"
    } catch { Write-Warning "Снимок рабочего стола не получился: $($_.Exception.Message)" }
}

function Start-Tauri {
    $env:SAVESTORIES_APP_SUPPORT = $data
    $env:SAVEME_CDP_PORT = "9222"
    return Start-Process -FilePath $exe -PassThru
}

function Stop-Tauri($proc) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Get-Process -Name msedgewebview2 -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $proc.Id } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

# ---- Фаза 1: запуск, экраны, добавление в очередь
Write-Host "== Фаза 1: первый запуск =="
$app = Start-Tauri
& $node $script "--playwright=$playwright" "--out=$OutDir" "--phase=first"
$phase1 = $LASTEXITCODE
Save-DesktopScreenshot "desktop-tauri"
$idle = Measure-App $app.Id 8
Write-Host ("Tauri (после сценария, простой 8 с): процессов {0}, рабочий набор {1} МБ, частная память {2} МБ, CPU {3}% одного ядра" -f $idle.Processes, $idle.WorkingSetMB, $idle.PrivateMB, $idle.CpuPercentOfOneCore)
$queueFile = Join-Path $data "queue.json"
if (-not (Test-Path $queueFile)) { Write-Warning "queue.json не создан" } else { Write-Host "queue.json: $(Get-Content $queueFile -Raw)" }
Stop-Tauri $app

# ---- Фаза 2: перезапуск, очередь должна вернуться
Write-Host "== Фаза 2: перезапуск (процесс был убит без аккуратного завершения) =="
$app2 = Start-Tauri
& $node $script "--playwright=$playwright" "--out=$OutDir" "--phase=restored"
$phase2 = $LASTEXITCODE
$cold = Measure-App $app2.Id 5
Stop-Tauri $app2
Remove-Item Env:\SAVEME_CDP_PORT -ErrorAction SilentlyContinue

$report.Add("| Клиент | Процессов | Рабочий набор, МБ | Частная память, МБ | CPU в простое, % ядра |")
$report.Add("|---|---|---|---|---|")
$report.Add("| Tauri (после сценария) | $($idle.Processes) | $($idle.WorkingSetMB) | $($idle.PrivateMB) | $($idle.CpuPercentOfOneCore) |")
$report.Add("| Tauri (холодный запуск, 5 с) | $($cold.Processes) | $($cold.WorkingSetMB) | $($cold.PrivateMB) | $($cold.CpuPercentOfOneCore) |")

# ---- Экономия памяти: свёрнутое окно (Low, затем заморозка) и разворачивание
Add-Type -Namespace Win -Name User32 -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);'
Write-Host "== Свёрнутое окно =="
$minimizedOk = $true
try {
    $app3 = Start-Tauri
    & $node $script "--playwright=$playwright" "--out=$OutDir" "--phase=ping-start"
    if ($LASTEXITCODE -ne 0) { throw "интерфейс не поднялся" }
    $open = Measure-App $app3.Id 8
    $app3.Refresh()
    $hwnd = $app3.MainWindowHandle
    if ($hwnd -eq [System.IntPtr]::Zero) { throw "нет дескриптора окна" }
    [Win.User32]::ShowWindow($hwnd, 6) | Out-Null   # SW_MINIMIZE
    Start-Sleep -Seconds 3
    $min3 = Measure-App $app3.Id 3
    Start-Sleep -Seconds 25
    $min30 = Measure-App $app3.Id 3
    [Win.User32]::ShowWindow($hwnd, 9) | Out-Null   # SW_RESTORE
    Start-Sleep -Seconds 2
    & $node $script "--playwright=$playwright" "--out=$OutDir" "--phase=ping-restored"
    if ($LASTEXITCODE -ne 0) { $minimizedOk = $false; Write-Warning "После разворачивания интерфейс не отвечает" }
    $after = Measure-App $app3.Id 5
    foreach ($row in @(@("развёрнуто, 8 с в простое", $open), @("свёрнуто, через 3 с (Low)", $min3), @("свёрнуто, через 30 с (заморожено)", $min30), @("после разворачивания", $after))) {
        $m = $row[1]
        $report.Add("| Tauri: $($row[0]) | $($m.Processes) | $($m.WorkingSetMB) | $($m.PrivateMB) | $($m.CpuPercentOfOneCore) |")
        Write-Host ("Tauri {0}: рабочий набор {1} МБ, частная {2} МБ, CPU {3}%" -f $row[0], $m.WorkingSetMB, $m.PrivateMB, $m.CpuPercentOfOneCore)
    }
    Stop-Tauri $app3
} catch { $minimizedOk = $false; Write-Warning "Проверка свёрнутого окна не удалась: $($_.Exception.Message)" }

# ---- Сравнение с прежним WinUI-клиентом (поверх устанавливается он; сравнение — последний шаг)
if ($CompareWinUITag -ne "") {
    try {
        Write-Host "== Сравнение с WinUI $CompareWinUITag =="
        $old = Join-Path ([System.IO.Path]::GetTempPath()) "winui-setup.exe"
        Invoke-WebRequest -Uri "https://github.com/peregond/SaveStories/releases/download/$CompareWinUITag/SaveMe-Windows-Setup-$CompareWinUITag.exe" -OutFile $old
        $p = Start-Process -FilePath $old -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-" -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Установщик WinUI завершился с кодом $($p.ExitCode)" }
        $winui = Join-Path $installDir "SaveMe.WinUI.exe"
        if (-not (Test-Path $winui)) { throw "Нет $winui" }
        $w = Start-Process -FilePath $winui -PassThru
        Start-Sleep -Seconds 20
        $wm = Measure-App $w.Id 8
        Write-Host ("WinUI: процессов {0}, рабочий набор {1} МБ, частная память {2} МБ, CPU {3}%" -f $wm.Processes, $wm.WorkingSetMB, $wm.PrivateMB, $wm.CpuPercentOfOneCore)
        Save-DesktopScreenshot "desktop-winui"
        Stop-Process -Id $w.Id -Force -ErrorAction SilentlyContinue
        $report.Add("| WinUI $CompareWinUITag (20 с после запуска) | $($wm.Processes) | $($wm.WorkingSetMB) | $($wm.PrivateMB) | $($wm.CpuPercentOfOneCore) |")
    } catch { Write-Warning "Сравнение с WinUI пропущено: $($_.Exception.Message)" }
}

$ui1 = Get-Content (Join-Path $OutDir "ui-first.json") -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
$summary = @("### Проверка установленного приложения на Windows", "", ($report -join "`n"), "",
    "Режим окна: ``data-glass=$($ui1.info.glass)``, тема ``$($ui1.info.theme)``, размер $($ui1.info.width)x$($ui1.info.height) при масштабе $($ui1.info.dpr).", "",
    "Куча JS: $($ui1.info.jsHeapMB) МБ, элементов DOM: $($ui1.info.domNodes), DOMContentLoaded: $($ui1.info.loadMs) мс.", "")
$summary -join "`n" | Set-Content (Join-Path $OutDir "metrics.md") -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { $summary -join "`n" | Add-Content $env:GITHUB_STEP_SUMMARY -Encoding UTF8 }
Write-Host ($summary -join "`n")

if (-not $minimizedOk) { throw "Свёрнутое окно: интерфейс не вернулся после разворачивания (или не поднялся)." }
if ($phase1 -ne 0 -or $phase2 -ne 0) { throw "Сценарий в интерфейсе не прошёл (фаза 1: $phase1, фаза 2: $phase2). Подробности в логе и ui-*.json." }
Write-Host "Проверка установленного приложения пройдена."
