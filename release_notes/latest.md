## SaveMe 0.6.65

- Windows: исправлен запуск WinUI-клиента, если сохранённая папка выгрузки находится на недоступном диске или в сломанном Google Drive shortcut; приложение сбрасывает путь на `Downloads\SaveMe` и продолжает открываться.
- Windows: удаление приложения теперь чистит локальные и roaming-данные SaveMe, WinUI-кэш, legacy-папки SaveStories/DimaSave, runtime/cache директории и настройки приложения в реестре.
- Windows: uninstall закрывает запущенные процессы SaveMe/legacy-клиентов и не падает, если процесса уже нет.
- Release: версия проекта, Node worker и macOS bundle metadata подняты до `0.6.65`.
