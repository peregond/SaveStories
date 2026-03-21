# SaveStories

`SaveStories` — desktop-приложение для выгрузки активных Instagram Stories через локальный `Playwright` worker.

Текущее состояние репозитория:

- версия исходников: `0.4.5`
- платформы: `macOS` и `Windows`
- общий runtime: `Node 24 LTS + Playwright + Chromium`

## Что уже умеет

- вход в Instagram через встроенный сценарий авторизации
- проверка и сохранение Instagram-сессии
- выгрузка активных stories по ссылке на профиль или `username`
- пакетная очередь профилей
- отдельные подпапки для каждого профиля
- сохранение `manifest`-файлов для скачанных media
- экран `Главная 2.0` для более удобного пакетного сценария
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

- [node_worker/bridge.mjs](/Users/peregon/Documents/DimaSave/node_worker/bridge.mjs)

## Структура проекта

- [Sources](/Users/peregon/Documents/DimaSave/Sources) — исходники macOS-приложения
- [windows_app](/Users/peregon/Documents/DimaSave/windows_app) — Windows-клиент и сборочные скрипты
- [scripts](/Users/peregon/Documents/DimaSave/scripts) — сборка и упаковка macOS
- [packaging](/Users/peregon/Documents/DimaSave/packaging) — иконки, plist, DMG background и упаковочные утилиты
- [.github/workflows](/Users/peregon/Documents/DimaSave/.github/workflows) — GitHub Actions
- [VERSION](/Users/peregon/Documents/DimaSave/VERSION) — единый номер версии проекта

## Главная 2.0

Новый сценарий `Главная 2.0` доступен и в `macOS`, и в `Windows`.

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
swift run DimaSave
```

Локальная подготовка worker runtime:

```bash
./scripts/bootstrap_node_worker.sh
```

## Windows

Windows-версия лежит в:

- [windows_app](/Users/peregon/Documents/DimaSave/windows_app)

Она использует тот же общий worker и поддерживает:

- вход в Instagram
- проверку сессии
- выгрузку одного профиля
- пакетную очередь профилей
- `Главная 2.0`
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
dist/windows/SaveStories-Windows/SaveStories-Windows.exe
dist/windows/SaveStories-Windows-Setup-vX.Y.Z.exe
```

Подробнее:

- [windows_app/README.md](/Users/peregon/Documents/DimaSave/windows_app/README.md)

## GitHub Releases

Проект публикует обе платформы через `GitHub Releases`.

Workflow:

- [release-assets.yml](/Users/peregon/Documents/DimaSave/.github/workflows/release-assets.yml)

Что публикуется в релиз:

- `SaveStories-macOS-vX.Y.Z.dmg`
- `SaveStories-Windows-vX.Y.Z.zip`
- `SaveStories-Windows-Setup-vX.Y.Z.exe`
- `appcast-macos.xml` в ветку `update-feed`

Как выпустить новую версию:

1. Закоммитить изменения в `main`
2. Создать тег
3. Отправить тег в GitHub

Пример:

```bash
git add .
git commit -m "Prepare v0.4.6 release"
git pull --rebase origin main
git push origin main
git tag v0.4.6
git push origin v0.4.6
```

После этого GitHub Actions:

- создаст или обновит release
- соберёт macOS `.dmg`
- соберёт Windows `.zip`
- соберёт Windows installer `.exe`
- прикрепит артефакты в `Releases`
- обновит macOS appcast

## Автообновление

`macOS` использует `Sparkle`, а `Windows` проверяет `GitHub Releases` и умеет поставить portable-обновление после перезапуска приложения.

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
export DIMASAVE_BUNDLE_ID="com.example.savestories"
export DIMASAVE_VERSION="0.4.5"
export DIMASAVE_BUILD="61"
./scripts/build_release_dmg.sh
```

Итоговый файл:

```text
dist/release/SaveStories.dmg
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

- Windows README: [windows_app/README.md](/Users/peregon/Documents/DimaSave/windows_app/README.md)
- Release workflow: [.github/workflows/release-assets.yml](/Users/peregon/Documents/DimaSave/.github/workflows/release-assets.yml)
- Windows EXE workflow: [.github/workflows/windows-exe.yml](/Users/peregon/Documents/DimaSave/.github/workflows/windows-exe.yml)
