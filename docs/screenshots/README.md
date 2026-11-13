# Скриншоты SaveMe

Актуальные снимки интерфейса для README, релизов и презентаций. Версия на снимках: **0.6.95**.
Файлы можно брать прямо отсюда: нажмите на картинку, затем «Download» (или откройте `Raw` и сохраните).

## Как они сделаны

- **Windows** (`windows/`): тот же интерфейс, что в приложении, открытый в браузере с демо-данными (очередь профилей, файлы для обработки, ход обработки). В приложении под прозрачным окном находится системный материал Mica, поэтому в снимках под окном подставлен похожий фон. Размер 2400×1600 (окно 1200×800 при масштабе 2×). Настоящая рамка окна Windows в кадр не попала.
- **macOS** (`macos/`): настоящее окно приложения SaveMe (режим предпросмотра дизайна), снятое на macOS-раннере GitHub системной командой `screencapture`. Экран раннера всего 1024×768, поэтому окно снято по ширине 1500 пикселей, а по высоте обрезано экраном (около 674 пикселей). Файлы и ход обработки в «Уникализаторе» вымышленные. В «Настройках» строка про «предпросмотр дизайна» появляется из-за режима съёмки и в обычном приложении её нет.
- Тёмная и светлая темы, русский интерфейс. Английский — файлы с префиксом `en-`.

## Windows

| Светлая тема | Тёмная тема |
|---|---|
| ![Stories](windows/stories-light.png) | ![Stories](windows/stories-dark.png) |
| ![Reels](windows/reels-light.png) | ![Reels](windows/reels-dark.png) |
| ![Уникализатор](windows/unikalizator-light.png) | ![Уникализатор](windows/unikalizator-dark.png) |
| ![Уникализатор: ход обработки](windows/unikalizator-progress-light.png) | ![Уникализатор: ход обработки](windows/unikalizator-progress-dark.png) |
| ![Сортировка](windows/sorting-light.png) | ![Сортировка](windows/sorting-dark.png) |
| ![Настройки](windows/settings-light.png) | ![Настройки](windows/settings-dark.png) |

Английский интерфейс: [Stories](windows/en-stories-light.png), [Unikalizer](windows/en-unikalizator-light.png), [Settings](windows/en-settings-light.png).

## macOS

| Светлая тема | Тёмная тема |
|---|---|
| ![Stories](macos/main-light.png) | ![Stories](macos/main-dark.png) |
| ![Reels](macos/reels-light.png) | ![Reels](macos/reels-dark.png) |
| ![Уникализатор](macos/unikalizator-light.png) | ![Уникализатор](macos/unikalizator-dark.png) |
| ![Сортировка](macos/sorting-light.png) | ![Сортировка](macos/sorting-dark.png) |
| ![Настройки](macos/settings-light.png) | ![Настройки](macos/settings-dark.png) |

Английский интерфейс: [Stories](macos/en-main-light.png), [Unikalizer](macos/en-unikalizator-light.png). Узкое окно: [Уникализатор](macos/compact-unikalizator-light.png).

## Как обновить

- **macOS:** запустить workflow `.github/workflows/macos-screenshots.yml` (вручную или записью в файл `MACOS_SCREENSHOT_REQUEST` на ветке). Снимки появятся в артефакте `macos-screens`, папка `shots-repo`. Параметры съёмки — аргументы `--design-preview --preview-clean --preview-version=… --preview-section=… --preview-appearance=… --preview-language=…`.
- **Windows:** запустить интерфейс командой `npm run dev` в `windows_app_react` и открыть страницу с параметрами `?glass=native&theme=light|dark&page=…` (демо-режим: `queue=restore`, `unik=1`, `rules=1`); снимать в окне 1200×800 при масштабе 2×.
- После обновления не забудьте поправить версию в этом файле.
