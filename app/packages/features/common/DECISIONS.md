# Решения: features/common

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/AGENT.md](../../../../docs/tasks/AGENT.md#принятые-решения).

- Библиотека словарей (T-063): порт `DictionaryLibrary` (`list()`, `import(files, mode)`, `remove(id)`) и `ImportedDictionary(id, name, mode, wordCount, providerId)`, провайдер `dictionaryLibraryProvider`. `import` бросает `FormatException` (плохие файлы) и `FileSystemException` (нечитаемые).
- Шрифты (T-084): `loadUserFont(FontChoice)` — регистрирует файл в `FontLoader`, не бросает: нет файла или битый — `false` и `warning`; кэш по семейству и пути. `parseFontName`/`readFontName`/`readFontNameFromFile` → `FontName?` из таблицы `name` (nameID 16/17, иначе 1/2), битые данные — `null`. Общий для читалки и настроек, потому что фичи не импортируют друг друга.
- Секреты (T-092): `secretStoreProvider` в `port_providers.dart`, без override бросает `PortNotWiredError`.
- Журнал фраз (T-093): провайдер порта `phraseJournalProvider` (`PhraseJournal` из `core`); подключён в `bootstrap.dart` к `database.phraseJournal`.
- «Знаю» (T-098): `setTermStatusProvider` (`scenario_providers.dart`) — `SetTermStatus` из `termRepositoryProvider`, `levelDictionaryProvider` и `idGeneratorProvider`; не порт, в `bootstrap.dart` ничего не добавляется. Общий для модалки, истории и (T-099) шпаргалки.
- Последняя шпаргалка (T-118): провайдер порта `cheatSheetLogProvider` (`CheatSheetLog` из `core`); подключён в `bootstrap.dart` к `database.cheatSheetLog`, в демо — `FakeCheatSheetLog`.
