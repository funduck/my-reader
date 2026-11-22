# Решения: features/common

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/AGENT.md](../../../../docs/tasks/AGENT.md#принятые-решения).

- Библиотека словарей (T-063): порт `DictionaryLibrary` (`list()`, `import(files, mode)`, `remove(id)`) и `ImportedDictionary(id, name, mode, wordCount, providerId)`, провайдер `dictionaryLibraryProvider`. `import` бросает `FormatException` (плохие файлы) и `FileSystemException` (нечитаемые).
