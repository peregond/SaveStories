## SaveMe 0.6.21

- Добавлен структурный worker protocol v2 с `counts`, `batchResults`, `runtime` и `diagnostics` при сохранении обратной совместимости
- Усилены пакетные выгрузки: timeout изолирует зависшую страницу, добавлены retries/backoff и JSONL diagnostics
- Добавлены preflight/health checks для runtime, Playwright, Chromium, папок и session state
- Добавлен manifest schema v2, дедупликация между запусками и базовая integrity-проверка скачанных media
- Windows updater теперь требует SHA256 и проверяет подпись installer перед автоустановкой
