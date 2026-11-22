# Решения: features/cheatsheet

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/AGENT.md](../../../../docs/tasks/AGENT.md#принятые-решения).

- Экран разминки (T-054): `CheatSheetScreen({bookId, onRead, from, onWordTap})` из `package:features_cheatsheet/features_cheatsheet.dart`. `from == null` — сохранённая позиция, иначе начало книги. `onWordTap(context, LookupQuery)` — вызывающий показывает `showLookupSheet` (`router.dart`), так что фича не зависит от `lookup_sheet`; `LookupQuery` содержит слово, предложение из шпаргалки, режим из профиля и `sheet.from` как `locator`. Без `onWordTap` строки не нажимаются.
- `cheatSheetProvider((bookId:, from:))` открывает книгу через `OpenBook` из портов, строит `BuildCheatSheet(generator: cheatSheetGeneratorProvider, ...)`, закрывает книгу. Ошибка книги — `AsyncError`, экран пишет «Не удалось подготовить разминку.». `itemGlossProvider((text:, mode:))` берёт первое значение через `ProviderChain` без записи в журнал (в историю пишется только тап).
- Маршрут: `/cheatsheet/:bookId?locator=<json>` (`encodeLocatorParam`), «Читать» делает `pop`, а без истории — `go` в читалку. Тексты на русском, без l10n.
- В тестах провайдеры с фейками завершаются только через `tester.runAsync` (два круга: лист, затем толкования строк).
