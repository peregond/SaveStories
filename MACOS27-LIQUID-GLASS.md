# Liquid Glass — SDK 27 preview

## Редизайн (ноябрь 2026)

- Единая дизайн-система в `Sources/SaveStories/Views/SaveMeGlass.swift`: метрики, фирменный акцент, `saveMeGlassSurface`, `saveMeGlassButton`, `SaveMeGlassGroup`, фон `SaveMeBackdrop`.
- Все панели разделов — системное стекло (`glassEffect`) поверх статичного mesh-градиента; вложенные плитки и поля — лёгкие заливки без второго слоя стекла.
- Главные действия — `glassProminent` с фирменным акцентом, второстепенные — нейтральное стекло; кнопки-капсулы.
- Подзаголовок раздела в панели инструментов.
- Фон проходит под боковой панелью и панелью инструментов; `backgroundExtensionEffect` больше не используется (давал зеркальный артефакт).
- «Уменьшение прозрачности» / «Увеличение контраста» — плотные поверхности; macOS 14–15 — `regularMaterial`.
- Отладочную сборку для проверки вида собирать так же, как релиз: `swift build --build-system native --sdk "$(xcrun --sdk macosx --show-sdk-path)"` — иначе бинарник получает SDK 14 и система рисует окно в старом стиле.
- `--preview-onboarding` и `--preview-cleanup` в режиме `--design-preview` показывают диалог первого запуска и диалог удаления пустых папок.

### Анимации прогресса

- Полосы прогресса (очередь Stories, задания и общий ход Уникализатора, установка FFmpeg) плавно дотягиваются до нового значения; счётчики перекатывают цифры.
- Строка очереди: значок статуса сменяется с анимацией, у скачиваемого профиля разделитель становится бегущей полосой, список сам подъезжает к текущему профилю.
- Ход работы виден из любого раздела: счётчик «3/12» или индикатор в боковой панели, круговой прогресс в панели инструментов, число оставшихся профилей на значке в Dock.
- Смена раздела — короткое затухание. Всё отключается при «Уменьшении движения».
- `--design-preview --preview-demo-download` разыгрывает загрузку на вымышленных профилях (без сети и файлов).

### Уникализатор по шагам и сверка с Betrch Unik

- Раздел разбит на семь шагов: исходники, плашка 18+, формат, название файла, стиль, дополнительно, запуск (в онлайн-сервисе стиль входит в «Дополнительно»). Ход обработки и пресеты всегда справа.
- Стили выбираются карточками; на шаге «Стиль» есть предпросмотр первого исходника с приближённым эффектом (точный результат даёт только FFmpeg). Шаги с ошибкой отмечены в полосе шагов и в итоговой сводке.
- Из ядра Betrch Unik перенесены яркость, контраст и отражение по горизонтали (`unik_plan.mjs`, `unik_batch.mjs`, поле `adjust` в настройках); диапазоны длительности и заставки приведены к сервису.
- Не перенесено (серверные и веб-функции): миниатюры исходников, история заданий и архив в Google Drive, аккаунты.
- Интерфейс Windows новые поля пока не показывает; воркер общий, поэтому без них работает как раньше.
- `--preview-unik-step=N` открывает нужный шаг; `--preview-scroll=N` прокручивает страницу перед снимком. Внеэкранные снимки (`--preview-screenshot`) рисуются с плотными поверхностями, потому что системное стекло вне экрана выходит чёрным.

### Правки после ревью

- Тексты приведены к обращению на «вы», из интерфейса убраны «runtime», «воркер», «Playwright».
- Пустые «Логи» и «Последние загрузки» занимают одну строку. Строка очереди — значок состояния, профиль и одна строка пояснения.
- «Удалить пустые папки» вынесено из шагов сортировки в отдельную панель; шаги пронумерованы 1–5.
- «Очистить очередь» и «Удалить пустые папки» спрашивают подтверждение. По завершении загрузки приходит системное уведомление, если окно не на переднем плане (только в упакованном приложении).

### Live Activities

- По сообщениям о бете macOS 27.3, приложения Mac смогут запускать Live Activities через ActivityKit. В установленном SDK 27.2 весь ActivityKit помечен как недоступный на macOS, поэтому собрать это сейчас нельзя.
- Понадобится расширение WidgetKit внутри .app. Сейчас приложение собирается как исполняемый файл SwiftPM и упаковывается скриптами, так что сборку расширения придётся добавлять отдельно.

### Сверка с гайдом Hallmark (раздел «App screens»)

- Все цвета и кегли — через токены `SaveMePalette` и `Font.saveMe(_:)` (шкала 11/12/13/15/18/22); литералов в представлениях нет.
- Нет подписей капсом с разрядкой, точек-разделителей «·», стрелок и галочек в тексте кнопок, декоративных цветных точек. Значки в заголовках панелей оставлены по решению владельца — без подложки, в фирменном цвете.
- Нет плиток внутри панелей: списки — строки с разделителем, показатели — число табличными цифрами и подпись.
- Убраны шапки-приветствия разделов и карточка «Обзор» в настройках; название раздела и пояснение — в панели инструментов.
- Акцент только у основного действия, выделения и состояния; фон — нейтральный с одним зелёным оттенком, без сине-фиолетового градиента.
- Осталось на усмотрение владельца: подтверждение для «Очистить очередь» и «Удалить пустые папки» в «Сортировке», конфетти после выгрузки (декоративная анимация).

Updated September 18, 2026. Prepared for release 0.6.82.

- System glass / prominent glass button styles throughout the main screens, settings and sheets.
- Tinted interactive glass for download and secondary actions, with disabled-state treatment.
- Shared GlassEffectContainer for download/stop controls; motion respects Reduce Motion.
- Extended gradient behind navigation, 20-point content corners, retained SF Rounded and readable content surfaces.
- Opaque control fallbacks for Reduce Transparency / Increase Contrast and macOS versions before 26; minimum deployment remains macOS 14.

Validation: 46 Swift tests with Xcode 27; 7 packaging tests; light/dark visual inspection. Preview app and media helper report SDK 27.0, minimum OS 14.0, arm64; strict ad-hoc signature check passed. Real Instagram downloads were not part of visual validation.

Xcode 27 switches SwiftPM to swiftbuild, which creates structured resource bundles. Resource lookup and package validation now support both layouts. On this installation its linked binaries reported SDK 14.0 despite selecting SDK 27. Packaging explicitly uses the native SwiftPM backend and selected SDK; actual Mach-O metadata remains checked. Revisit this compatibility setting when updating the toolchain.

Sources: https://developer.apple.com/videos/play/wwdc2026/269/ and https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views

Build: `SAVEME_REQUIRE_SDK=27 SAVEME_REQUIRE_COMPOSED_ICON=1 ./scripts/build_beta_app.sh`
