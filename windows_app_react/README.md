# SaveMe Windows — React UI (прототип)

Новый интерфейс Windows-клиента на React + TypeScript + Vite. Дизайн повторяет macOS-версию:
градиентный фон, стеклянные карточки со скруглением 20 px, светлая/тёмная/системная тема.

Статус: готов только интерфейс (Stories, Очередь, Reels, Настройки) на демо-данных.
Старый PySide6-клиент (`windows_app/`) не тронут и продолжает выходить как раньше.

## Запуск

```bash
cd windows_app_react
npm install
npm run dev      # http://localhost:5173
npm run build    # проверка типов + сборка (~75 КБ gzip)
```

Параметры для проверки: `?theme=dark|light` и `?page=stories|queue|reels|settings`.

## Дальше

- Оболочка: Tauri (системный WebView2, без своего Chromium).
- `src/bridge.ts` — единственная точка связи с воркером; сейчас `createMockBridge`, затем вызовы Tauri `invoke` к `node_worker/bridge.mjs` (протокол как в `windows_app/savestories_windows/models.py`).
- Перенос: автообновление, настройки, блокировка сна, установщик.
