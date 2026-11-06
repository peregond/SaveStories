# Проверка раздела «Уникализатор» на Windows с настоящим FFmpeg: докачка из GitHub Releases, создание тестового видео,
# обработка (3 вариации + плашка 18+) и проверка результатов через ffprobe. Работает с установленным приложением.
# Запуск: ./windows_app_react/unik_e2e.ps1 [-OutDir unik-e2e]
param([string]$OutDir = "unik-e2e")
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$installDir = Join-Path $env:LOCALAPPDATA "Programs\SaveMeWindows"
$node = Join-Path $installDir "runtime\node\node.exe"
$bridge = Join-Path $installDir "node_worker\bridge.mjs"
foreach ($p in @($node, $bridge)) { if (-not (Test-Path $p)) { throw "Не найдено: $p" } }
$support = Join-Path $OutDir "support"
New-Item -ItemType Directory -Force -Path $support | Out-Null
$env:SAVESTORIES_APP_SUPPORT = $support
# PATH без системного ffmpeg: проверяем именно докачку
$env:PATH = ($env:PATH -split ";" | Where-Object { -not (Test-Path (Join-Path $_ "ffmpeg.exe")) }) -join ";"
$failed = New-Object System.Collections.Generic.List[string]
function Fail([string]$m) { Write-Host "FAIL $m"; $failed.Add($m) }
function Ok([string]$m) { Write-Host "OK   $m" }

function Invoke-Worker($request) {
    $json = $request | ConvertTo-Json -Depth 12 -Compress
    $errFile = Join-Path $OutDir "stderr.txt"
    $out = $json | & $node $bridge 2> $errFile
    $progress = @(Get-Content $errFile -ErrorAction SilentlyContinue | Where-Object { $_ -like "unik_*" })
    return [pscustomobject]@{ Response = ($out | ConvertFrom-Json); Progress = $progress }
}

# 1. До установки FFmpeg в приложении нет
$r = Invoke-Worker @{ command = "unik_status" }
if ($r.Response.data.ffmpegInstalled -eq "false") { Ok "до установки FFmpeg не найден" } else { Fail "FFmpeg найден до установки: $($r.Response.data.ffmpegPath)" }
$catalog = $r.Response.data.catalog | ConvertFrom-Json
if ($catalog.formatPresets.Count -eq 5 -and $catalog.stylePresets.Count -eq 8 -and $catalog.ageMarkGeos.Count -eq 9) { Ok "каталог на месте (5 форматов, 8 стилей, 9 стран)" } else { Fail "каталог неполный" }
$marks = Join-Path $installDir "node_worker\unik_assets\age-marks"
$markCount = @(Get-ChildItem $marks -Filter *.png -ErrorAction SilentlyContinue).Count
if ($markCount -eq 54) { Ok "шаблоны плашек 18+ установлены (54)" } else { Fail "шаблонов плашек: $markCount, ожидалось 54" }

# 2. Докачка FFmpeg
$r = Invoke-Worker @{ command = "unik_install_ffmpeg" }
$r.Progress | Select-Object -First 3 | ForEach-Object { Write-Host "     $_" }
if ($r.Response.ok) { Ok "FFmpeg установлен: $($r.Response.data.ffmpegVersion)" } else { throw "Установка FFmpeg не удалась: $($r.Response.message)" }
$ffmpeg = Join-Path $support "ffmpeg\bin\ffmpeg.exe"
$ffprobe = Join-Path $support "ffmpeg\bin\ffprobe.exe"
if ((Test-Path $ffmpeg) -and (Test-Path $ffprobe)) { Ok "ffmpeg.exe и ffprobe.exe в папке приложения" } else { throw "Нет ffmpeg.exe/ffprobe.exe после установки" }
$r = Invoke-Worker @{ command = "unik_status" }
if ($r.Response.data.ffmpegInstalled -eq "true" -and $r.Response.data.libx264 -eq "true") { Ok "статус: FFmpeg готов, libx264 есть" } else { Fail "после установки статус: $($r.Response.data.ffmpegInstalled), libx264: $($r.Response.data.libx264)" }

# 3. Тестовое видео и картинка
$src = Join-Path $OutDir "clip.mp4"
& $ffmpeg -y -v error -f lavfi -i "testsrc=size=720x1280:rate=30:duration=3" -f lavfi -i "sine=frequency=440:duration=3" -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest $src
if (-not (Test-Path $src)) { throw "Не удалось создать тестовое видео" }
$pic = Join-Path $OutDir "pic.png"
& $ffmpeg -y -v error -f lavfi -i "testsrc=size=500x500:rate=1:duration=1" -frames:v 1 $pic

# 4. Обработка: 3 вариации, плашка 18+, структурные имена
$out = Join-Path $OutDir "result"
$r = Invoke-Worker @{ command = "unik_process"; sources = @($src, $pic); outputDirectory = $out; options = @{
    formatPresetId = "meta-story"; bitrate = "1.5M"
    variations = @{ count = 3; styleIds = @("soft", "cinematic", "bright"); mode = "all-variations" }
    ageMark = @{ enabled = $true; geoId = "de-germany"; position = "bottom" }
    naming = @{ mode = "structured"; geo = "DE"; presetToken = "meta"; versionToken = "v1" } } }
Write-Host "     $($r.Response.message)"
$results = $r.Response.data.results | ConvertFrom-Json
$done = @($results | Where-Object { $_.status -eq "completed" })
if ($done.Count -eq 6) { Ok "создано 6 файлов (2 исходника × 3 вариации)" } else { Fail "создано $($done.Count) из 6: $($r.Response.message)" }
if ($r.Progress -contains "unik_total=6") { Ok "прогресс воркера дошёл до интерфейса (unik_total=6)" } else { Fail "нет строки unik_total=6" }

# 5. Проверка результатов ffprobe: размер, кодек, звук, длительность
foreach ($res in $done) {
    $info = & $ffprobe -v error -show_entries stream=codec_name,width,height -show_entries format=duration -of json $res.outputPath | ConvertFrom-Json
    $v = $info.streams | Where-Object { $_.codec_name -in @("h264", "png") } | Select-Object -First 1
    $name = Split-Path $res.outputPath -Leaf
    if ($v.width -eq 1080 -and $v.height -eq 1920) { Ok "$name — 1080x1920, $($v.codec_name)" } else { Fail "$name — размер $($v.width)x$($v.height), ожидалось 1080x1920" }
}
$videoOutputs = @($done | Where-Object { $_.outputPath -like "*.mp4" })
if ($videoOutputs.Count -eq 3) {
    $durations = $videoOutputs | ForEach-Object { [double](& $ffprobe -v error -show_entries format=duration -of csv=p=0 $_.outputPath) }
    if ($durations[1] -gt $durations[0] -and $durations[2] -lt $durations[0]) { Ok "стили меняют длительность: Кино длиннее, Яркий короче Мягкого ($($durations -join ' / '))" } else { Fail "длительности не отличаются как ожидалось: $($durations -join ' / ')" }
}
$names = ($done | ForEach-Object { Split-Path $_.outputPath -Leaf }) -join ", "
Write-Host "     файлы: $names"
if ($names -match "DE_meta_9x16_v1") { Ok "имена по схеме ГЕО_пресет_размер_версия" } else { Fail "имена не по схеме: $names" }

# 6. Кадр с плашкой — для просмотра в артефактах
& $ffmpeg -y -v error -i $videoOutputs[0].outputPath -ss 1 -frames:v 1 (Join-Path $OutDir "frame-with-age-mark.png")
Copy-Item (Join-Path $OutDir "stderr.txt") (Join-Path $OutDir "worker-progress.txt") -ErrorAction SilentlyContinue

if ($failed.Count -gt 0) { throw "Проверка «Уникализатора» не прошла: " + ($failed -join "; ") }
Write-Host "Проверка «Уникализатора» на Windows пройдена."
