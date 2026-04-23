# SaveMe

`SaveMe` — desktop-приложение для выгрузки активных Instagram Stories через локальный `Playwright` worker.

Текущее состояние репозитория:

- версия исходников: `0.6.19`
- платформы: `macOS` и `Windows`
- общий runtime: `Node 24 LTS + Playwright + Chromium`

## Что уже умеет

- вход в Instagram через встроенный сценарий авторизации
- проверка и сохранение Instagram-сессии
- выгрузка активных stories по ссылке на профиль или `username`
- пакетная очередь профилей
- отдельные подпапки для каждого профиля
- сохранение `manifest`-файлов для скачанных media
- экран `Главная` для более удобного пакетного сценария
- сохранение недавних списков профилей для повторной выгрузки
- статусная строка с текущим шагом и состоянием очереди
- анимация завершения с конфетти и коротким звуком успеха
- автообновление `macOS` через `Sparkle`
- автообновление `Windows` через `GitHub Releases`

## Архитектура

- `SwiftUI`-приложение для `macOS`
- `PySide6`-клиент для `Windows`
- общий `Node 24 LTS` worker
- `Playwright` + `Chromium`
- локальный persistent browser profile

Основной worker:

- [node_worker/bridge.mjs](/Users/peregon/Documents/SaveStories/node_worker/bridge.mjs)

## Структура проекта

- [Sources](/Users/peregon/Documents/SaveStories/Sources) — исходники macOS-приложения
- [windows_app](/Users/peregon/Documents/SaveStories/windows_app) — Windows-клиент и сборочные скрипты
- [scripts](/Users/peregon/Documents/SaveStories/scripts) — сборка и упаковка macOS
- [packaging](/Users/peregon/Documents/SaveStories/packaging) — иконки, plist, DMG background и упаковочные утилиты
- [.github/workflows](/Users/peregon/Documents/SaveStories/.github/workflows) — GitHub Actions
- [VERSION](/Users/peregon/Documents/SaveStories/VERSION) — единый номер версии проекта

## Главная

Новый сценарий `Главная` доступен и в `macOS`, и в `Windows`.

Что в нём есть:

- единая форма для пакетной вставки ссылок и usernames
- выбор режима выгрузки
- быстрый запуск очереди
- компактная статусная строка
- недавние наборы профилей
- переиспользование уже сохранённых списков

Этот экран предназначен как более понятный стартовый сценарий для новых пользователей.

## macOS

macOS-версия собирается как `.app` и пакуется в `.dmg`.

Что внутри release-сборки:

- встроенный runtime worker
- встроенный `Playwright`
- встроенный `Chromium`
- `Sparkle` для автообновлений

То есть release-сборка рассчитана на автономный запуск без ручной установки зависимостей.

Локальный запуск из исходников:

```bash
./scripts/run_app.sh
```

Или напрямую:

```bash
swift run SaveMe
```

Локальная подготовка worker runtime:

```bash
./scripts/bootstrap_node_worker.sh
```

## Windows

Windows-версия лежит в:

- [windows_app](/Users/peregon/Documents/SaveStories/windows_app)

Она использует тот же общий worker и поддерживает:

- вход в Instagram
- проверку сессии
- выгрузку одного профиля
- пакетную очередь профилей
- `Главная`
- повторное использование недавних списков
- проверку и установку обновлений

Сборка `.exe` на Windows:

```powershell
cd windows_app
./build_windows.ps1
```

Сборка установщика:

```powershell
cd windows_app
./build_windows_installer.ps1
```

Основные результаты:

```text
dist/windows/SaveMe-Windows/SaveMe-Windows.exe
dist/windows/SaveMe-Windows-Setup-vX.Y.Z.exe
```

Подробнее:

- [windows_app/README.md](/Users/peregon/Documents/SaveStories/windows_app/README.md)

## GitHub Releases

Проект публикует обе платформы через `GitHub Releases`.

Workflow:

- [release-assets.yml](/Users/peregon/Documents/SaveStories/.github/workflows/release-assets.yml)

Что публикуется в релиз:

- `SaveMe-macOS-vX.Y.Z.dmg`
- `SaveMe-Windows-WinUI-Beta-Setup-vX.Y.Z.exe`
- `SaveMe-Windows-Setup-vX.Y.Z.exe`
- `appcast-macos.xml` в ветку `update-feed`

Как выпустить новую версию:

1. Закоммитить изменения в `main`
2. Создать тег
3. Отправить тег в GitHub

Пример:

```bash
git add .
git commit -m "Prepare v0.6.19 release"
git pull --rebase origin main
git push origin main
git tag v0.6.19
git push origin v0.6.19
```

После этого GitHub Actions:

- создаст или обновит release
- соберёт macOS `.dmg`
- соберёт Windows `.zip`
- соберёт Windows installer `.exe`
- прикрепит артефакты в `Releases`
- обновит macOS appcast

## Автообновление

`macOS` использует `Sparkle`, а `Windows` проверяет `GitHub Releases`.

Для `Windows` автоустановка работает только у версии, установленной через `SaveMe-Windows-Setup-vX.Y.Z.exe`.
Если приложение запущено из portable-папки или распакованного архива, оно сможет проверить наличие новой версии, но установщик нужно будет скачать и запустить вручную.

Для обновлений `macOS` нужен локальный signing key и GitHub secret:

```bash
./scripts/generate_update_keys.sh
```

После этого:

1. Возьми содержимое файла `.update-signing/ed25519-private.pem`
2. Добавь его в GitHub repository secret `UPDATE_SIGNING_PRIVATE_KEY`
3. Следующий релиз автоматически обновит feed в ветке `update-feed`

## Релизная сборка macOS вручную

Без подписи и notarization:

```bash
./scripts/build_release_dmg.sh
```

С подписью и notarization:

```bash
export APPLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_NOTARY_PROFILE="savestories-notary"
export SAVESTORIES_BUNDLE_ID="com.example.savestories"
export SAVESTORIES_VERSION="0.6.19"
export SAVESTORIES_BUILD="74"
./scripts/build_release_dmg.sh
```

Итоговый файл:

```text
dist/release/SaveMe.dmg
```

## Локальная разработка

Для запуска из исходников нужен `Node 24 LTS`.

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
- Основной сценарий проекта — выгрузка именно активных stories по профилю.

## Дополнительно

- Windows README: [windows_app/README.md](/Users/peregon/Documents/SaveStories/windows_app/README.md)
- Release workflow: [.github/workflows/release-assets.yml](/Users/peregon/Documents/SaveStories/.github/workflows/release-assets.yml)
- Windows EXE workflow: [.github/workflows/windows-exe.yml](/Users/peregon/Documents/SaveStories/.github/workflows/windows-exe.yml)
