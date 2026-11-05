# SaveMe Windows — React + Tauri (прототип)

Новый клиент Windows на **React + TypeScript + Vite** в оболочке **Tauri 2** (системный WebView2, без Electron).
Дизайн повторяет macOS-версию: градиентный фон, стеклянные карточки, светлая/тёмная/системная тема.

> **Статус: прототип, не заменяет выпускаемый клиент.** Релизы Windows сейчас собираются из `windows_app_winui_beta/`
> (WinUI 3). Этот клиент по возможностям соответствует устаревшему PySide6-клиенту (`windows_app/`):
> Stories, Очередь, Reels, Настройки. **Не перенесено из WinUI:** раздел «Сортировка» (Notion-правила,
> Google Drive, раскладка файлов), очередь из Notion, очистка пустых папок, установка Chromium после инсталляции.

## Что работает

- Интерфейс: Stories, Очередь, Reels, Настройки (`src/`), демо-режим в браузере.
- Rust-бэкенд (`src-tauri/`): запуск `node_worker/bridge.mjs` (JSON в stdin → JSON в stdout, прогресс из stderr),
  отмена с остановкой дерева процессов, вход в Instagram отдельным окном, настройки (`settings.json`,
  импорт из реестра старого клиента), запрет сна на время выгрузки, автообновление из GitHub Releases
  (SHA256 + Authenticode, ключи Inno Setup как у старого клиента).
- Тесты: `cargo test` (16), `npm test` (7).

## Чего нет

- Сборки Windows-установщика и CI-воркфлоу для неё (план: `tauri build --no-bundle` → папка с `node_worker`,
  `runtime/node`, `runtime/ms-playwright` → существующий Inno Setup).
- Проверки на реальной Windows: установщик, автообновление, запрет сна, taskkill дерева процессов.
- Полной выгрузки с реальным Instagram и Chromium (в среде разработки Chromium нет).

## Запуск

```bash
npm install
npm run dev          # интерфейс в браузере с демо-данными
npm test             # тесты разбора ссылок
cd src-tauri && cargo test --lib
npm run tauri dev    # приложение целиком (нужны Rust и Node; на Windows — WebView2)
```

Демо-параметры: `?theme=dark|light`, `?page=stories|queue|reels|settings`, `?session=none`, `?fail=1`.
