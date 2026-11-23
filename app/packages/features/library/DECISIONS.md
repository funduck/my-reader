# Решения: features/library

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/AGENT.md](../../../../docs/tasks/AGENT.md#принятые-решения).

- Библиотека (T-019): `ImportBook({adapters, books, clock, ids, directory, hash})`, `call(path)` → sealed `ImportOutcome` (`BookImported` / `BookAlreadyImported` / `BookUnsupported`); бросается только `FileSystemException`. Файл — `<directory>/<hash>.<format>`, хеш внедряется (`sha256OfFile` в `features_library`). `main.dart` асинхронный: `bootstrap(overrides: [...buildOverrides(), ...await buildDeviceOverrides()])`; `buildDeviceOverrides` открывает drift в `<applicationSupport>/my_reader.sqlite` и подключает репозитории, `EpubFormatAdapter`, `booksDirectoryProvider` (`<applicationSupport>/books`). Новые устройство-зависимые порты добавляются туда же. `LibraryScreen({onOpenBook})` — навигацию делает `router.dart`.
- Кнопки шапки (T-101): `onOpenHistory`, `onOpenSettings` — необязательные `VoidCallback`; без них кнопок нет.
