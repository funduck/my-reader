# Решения: reader_api

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/README.md](../../../docs/tasks/README.md#принятые-решения).

- `reader_api` (T-015): `ReaderEngine` (`buildView`, `load(book, {required bookId, at})` (с T-017), `goTo`, `applySettings`, `highlight(List<Locator>)` заменяет прежний набор, `events` — broadcast, `dispose` один раз). `load` не закрывает `OpenedBook`. `ReaderSettings`: `fontFamily` (null — шрифт движка), `fontSize` = 18, `theme` (`ReaderTheme.light/dark`), `horizontalPadding` = 16; расширять только аддитивно.
