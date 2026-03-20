# DimaSave

`DimaSave` — десктопное приложение для выгрузки активных stories из Instagram через локальный `Playwright` worker.

Текущая версия проекта:

- `0.2.4`

## Что уже умеет

- вход в Instagram через встроенный сценарий авторизации
- проверка сохранённой сессии
- выгрузка активных stories по ссылке на профиль или username
- пакетная очередь профилей
- отдельные подпапки для каждого профиля
- сохранение `manifest`-файла для каждого скачанного media
- отдельная версия для `macOS`
- отдельная версия для `Windows`

## Архитектура

- `SwiftUI`-приложение для `macOS`
- `PySide6`-клиент для `Windows`
- общий `Node 24 LTS` worker
- `Playwright` + `Chromium`
- локальный persistent browser profile

Основной worker:

- [bridge.mjs](node_worker/bridge.mjs)

## Структура проекта

- [Sources](Sources) — исходники macOS-приложения
- [windows_app](windows_app) — Windows-клиент и сборочные скрипты
- [scripts](scripts) — сборка и упаковка macOS
- [packaging](packaging) — иконки, plist и упаковочные утилиты
- [.github/workflows](.github/workflows) — GitHub Actions
- [VERSION](VERSION) — единый номер версии проекта

## macOS

macOS-версия собирается как `.app` и пакуется в `.dmg`.

Что внутри release-сборки:

- встроенный `node`
- встроенный `node_worker`
- встроенный `Playwright`
- встроенный `Chromium`

То есть release-сборка рассчитана на автономный запуск без отдельной установки `Node.js`.

Локальный запуск из исходников:

```bash
./scripts/run_app.sh
```

Или напрямую:

```bash
swift run DimaSave
```

Локальная подготовка worker runtime:

```bash
./scripts/bootstrap_node_worker.sh
```

## Windows

Windows-версия лежит в:

- [windows_app](windows_app)

Она использует тот же `Node 24 LTS` worker и сейчас поддерживает:

- видимый вход в Instagram
- проверку сессии
- выгрузку одного профиля
- пакетную очередь профилей
- остановку текущего элемента очереди

Сборка `.exe` на Windows:

```powershell
cd windows_app
./build_windows.ps1
```

Основной артефакт:

```text
dist/windows/DimaSave-Windows/DimaSave-Windows.exe
```

Подробнее:

- [windows_app/README.md](windows_app/README.md)

## GitHub Releases

Проект умеет автоматически публиковать обе версии в `GitHub Releases`.

Workflow:

- [.github/workflows/release-assets.yml](.github/workflows/release-assets.yml)

Что публикуется в релиз:

- `DimaSave-macOS-vX.Y.Z.dmg`
- `DimaSave-Windows-vX.Y.Z.zip`

Как выпустить новую версию:

1. Закоммитить изменения в `main`
2. Создать тег
3. Отправить тег в GitHub

Пример:

```bash
git add .
git commit -m "Prepare v0.2.4 release"
git pull --rebase origin main
git push origin main
git tag v0.2.4
git push origin v0.2.4
```

После этого GitHub Actions:

- создаст или обновит release
- соберёт macOS `.dmg`
- соберёт Windows `.zip`
- прикрепит оба файла в раздел `Releases`

Также workflow можно запускать вручную из GitHub Actions и передавать тег, например `v0.2.4`.

## Релизная сборка macOS вручную

Без подписи и notarization:

```bash
./scripts/build_release_dmg.sh
```

С подписью и notarization:

```bash
export APPLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_NOTARY_PROFILE="dimasave-notary"
export DIMASAVE_BUNDLE_ID="com.example.dimasave"
export DIMASAVE_VERSION="0.2.4"
export DIMASAVE_BUILD="39"
./scripts/build_release_dmg.sh
```

Итоговый файл:

```text
dist/release/DimaSave.dmg
```

## Локальная разработка

Для запуска из исходников сейчас нужен `Node 24 LTS`, потому что downloader runtime уже переведён на `Node worker`.

Подготовить локальный worker:

```bash
./scripts/bootstrap_node_worker.sh
```

Старый алиас тоже оставлен для совместимости:

```bash
./scripts/bootstrap_worker.sh
```

## Важные замечания

- Worker хранит persistent browser profile в локальной папке приложения.
- Для каждого media создаётся отдельный `manifest` с метаданными и `sha256`.
- Приложение не пытается обходить challenge-экраны, антибот-защиту или приватные ограничения доступа.
- На данный момент основной сценарий — выгрузка именно активных stories по профилю.

## Дополнительно

- Windows README: [windows_app/README.md](windows_app/README.md)
- Release workflow: [.github/workflows/release-assets.yml](.github/workflows/release-assets.yml)
- Windows EXE workflow: [.github/workflows/windows-exe.yml](.github/workflows/windows-exe.yml)
