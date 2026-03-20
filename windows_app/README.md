# SaveStories для Windows

Эта папка содержит Windows-клиент `SaveStories`.

## Что внутри

- desktop UI на `PySide6`
- общий downloader runtime на `Node 24 LTS`
- `Playwright` + `Chromium`
- пакетная очередь профилей
- логин в Instagram, проверка сессии и выгрузка активных stories

Основной worker:

- [node_worker/bridge.mjs](../node_worker/bridge.mjs)

## Локальный запуск из исходников

Для локальной разработки на Windows нужны:

- `Python 3.13+` для самого Windows-shell
- `Node 24 LTS` для общего worker runtime

Запуск:

```powershell
cd windows_app
./run_windows.ps1
```

## Подготовка worker runtime

```powershell
cd windows_app
./bootstrap_node_worker.ps1
```

Совместимый старый алиас тоже оставлен:

```powershell
cd windows_app
./bootstrap_worker.ps1
```

После этого браузеры `Playwright` ставятся в:

```text
%LOCALAPPDATA%\DimaSave\worker\ms-playwright
```

## Сборка `.exe`

```powershell
cd windows_app
./build_windows.ps1
```

Основной результат:

```text
dist/windows/SaveStories-Windows/SaveStories-Windows.exe
```

Полная папка сборки:

```text
dist/windows/SaveStories-Windows/
```

## GitHub Actions

Windows-сборка автоматически собирается в workflow:

- [windows-exe.yml](../.github/workflows/windows-exe.yml)

А релизный архив с Windows-версией прикрепляется через:

- [release-assets.yml](../.github/workflows/release-assets.yml)

## Что важно

- Во время обычного запуска пользователю не нужен установленный `Node.js`, если используется релизная сборка.
- `Python` нужен только для сборки Windows-shell и для локальной разработки из исходников.
