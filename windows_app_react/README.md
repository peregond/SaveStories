# SaveMe Windows — React + Tauri

Клиент Windows на **React + TypeScript + Vite** в оболочке **Tauri 2** (системный WebView2, без Electron).
Дизайн повторяет macOS-версию: градиентный фон, стеклянные карточки, светлая/тёмная/системная тема.
Бэкенд на Rust, выгрузка — прежний `node_worker` (Node + Playwright).

> **Статус: готов к проверке на Windows, релизный клиент пока не заменён.** Выпускаемый клиент —
> `windows_app_winui_beta/` (WinUI 3); этот проект собирается отдельным воркфлоу и не затрагивает релизы.
> Установщик использует тот же `AppId` и папку, что и WinUI, поэтому встанет поверх него.

## Паритет с WinUI-клиентом

| Возможность | Статус |
|---|---|
| Stories: очередь профилей, режим браузера, тип медиа, папка, повтор ошибочных, недавние наборы | ✅ |
| Живой прогресс по профилям (`batch_slot_*`), счётчики файлов и папок | ✅ |
| «Списочная» | ✅ *общая очередь и параметры со Stories* (в WinUI — отдельная очередь с фиксированными параметрами) |
| Reels: очередь ссылок, повтор ошибочных | ✅ |
| Сортировка: пустые папки, «На перенос» → «WhiteList INF», правила, раскладка, отмена, список, ссылки Google Drive | ✅ |
| Notion: автосписок инфлюенсеров и автоправила (не чаще раза в день, кэш) | ✅ |
| Предложение удалить пустые папки после выгрузки | ✅ |
| Вход в Instagram, проверка сессии | ✅ |
| Установка Chromium после инсталляции | ✅ *только Chromium: Node и зависимости воркера идут в установщике* |
| Проверка готовности, экспорт диагностики | ✅ *формат отчёта упрощён* |
| Тема: системная / светлая / тёмная / по времени суток (7–19) | ✅ |
| Автообновление из GitHub Releases (SHA256 + Authenticode, ключи Inno Setup) | ✅ |
| Запрет сна на время выгрузки | ✅ |
| Импорт настроек WinUI (`%LOCALAPPDATA%\SaveMe.WinUI\settings.json`) и старого Python-клиента | ✅ |

Осознанные отличия: файл, уже лежащий в нужной папке, не переименовывается в «имя 2» при повторной сортировке;
ссылка `https://…` в строке правил Notion не режется по двоеточию; порядок сортировки списков — по нижнему регистру
(в C# — по культуре).

## Структура

- `src/` — интерфейс. `store.ts` и `sorting.ts` — состояние, `api.ts` — единственная связь с бэкендом (в браузере вместо
  Tauri работает `demoApi.ts`), `parse.ts` — разбор ссылок по правилам WinUI.
- `src-tauri/src/` — бэкенд: `worker.rs` (запуск воркера, отмена, таймаут), `sorting.rs`, `notion.rs`, `cleanup.rs`,
  `gdrive.rs`, `runtime.rs` (Chromium, готовность), `settings.rs`, `updater.rs`, `sleep.rs`, `paths.rs`.
- `SaveMe-Tauri.iss`, `build_windows.ps1` — установщик (Inno Setup) и сборка.

## Запуск и проверки

```bash
npm install
npm run dev            # интерфейс в браузере с демо-данными
npm test               # тесты разбора ссылок и вспомогательных функций
cd src-tauri && cargo test --lib          # тесты бэкенда
cd src-tauri && cargo test --lib live -- --ignored --nocapture   # живой запрос к Notion
npm run tauri dev      # приложение целиком (Rust, Node; на Windows — WebView2)
```

Демо-параметры: `?theme=dark|light`, `?page=stories|queue|reels|sorting|settings`, `?session=none`, `?fail=1`,
`?chromium=none`, `?notion=1`, `?empty=1`, `?rules=1`.

## Сборка установщика (Windows)

```powershell
./windows_app_react/build_windows.ps1            # приложение + установщик (нужны Node 24, Rust, Inno Setup 6)
./windows_app_react/build_windows.ps1 -SkipInstaller
```

В CI: воркфлоу **Build Windows (React + Tauri)** — вручную или по тегу `tauri-v*` (тогда создаётся prerelease).
Проверки на PR — воркфлоу **Windows React CI** (Linux и Windows).

Чтобы выпускать этот клиент вместо WinUI, в `.github/workflows/release-assets.yml` замените job `build-windows-winui` шагами
из `windows-tauri.yml` (имя ассета `SaveMe-Windows-Setup-<tag>.exe` и `.sha256` остаётся тем же, поэтому старые клиенты обновятся).

При смене версии правьте: `VERSION`, `windows_app_react/package.json`, `src-tauri/tauri.conf.json`, `src-tauri/Cargo.toml`
(и `Cargo.lock` через `cargo update -p saveme-windows`); `scripts/check_version_consistency.py` проверяет совпадение.

## Что проверено и что нет

Проверено в среде разработки (Linux): 44 теста Rust, 17 тестов интерфейса, кросс-проверка компиляции под Windows
(`cargo check --target x86_64-pc-windows-gnu`), запуск приложения под виртуальным дисплеем с настоящим воркером и Chromium
(`environment`, `check_session` → «Нужен вход»), живой запрос к Notion (194 правила, 122 профиля).

**Не проверено — нужна Windows:** сборка установщика и установка WebView2, запуск `.exe`, автообновление поверх установленной
версии, запрет сна, остановка дерева процессов (`taskkill`), чтение NTFS-потоков Google Drive, вход в Instagram и реальная выгрузка.
