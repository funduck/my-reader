# Решения: features_reader

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/README.md](../../../../docs/tasks/README.md#принятые-решения).

- Экран (T-020): `ReaderScreen({bookId, locator})`. `OpenBook` и `SaveProgress` (`core/application`) берутся через `openBookProvider`/`saveProgressProvider`, собранные из общих портов. `OpenBook` → sealed `OpenBookOutcome` (`BookOpened(book, opened, resumeAt)` / `BookNotFound` / `BookFileUnreadable`). `SaveProgress.call(locator, {chapterCount})`: `percent = (chapter.index + progression) / chapterCount`. Позиция: `locator` маршрута важнее сохранённой; `engine.load(book, bookId:, at:)`. Сохранение — через 1 с после последнего `PositionChanged`, при `paused`/`hidden`/`detached` и в `dispose` (потом движок закрывается). У `ReaderEngine` нет `currentLocator()`, поэтому при закрытии сохраняется последний `PositionChanged` (движок шлёт не чаще раза в 500 мс). `WordTapped`/`TextSelected` экран пока не обрабатывает — T-047.
