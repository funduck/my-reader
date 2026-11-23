# Решения: features/history

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/AGENT.md](../../../../docs/tasks/AGENT.md#принятые-решения).

- История (T-070): `HistoryScreen({onOpenLocation})` из `package:features_history/features_history.dart`; колбэк получает `event.query.locator` строки контекста, без колбэка строки не нажимаются. `historyProvider(BookId?)` собирает термины, весь журнал и книги в памяти; фильтр по книге — локальное состояние экрана, `LookupFilter` не используется. `lookupJournalProvider` и `termRepositoryProvider` проведены в `buildDeviceOverrides`.
- Без перевода в строке слова (T-096): строка термина — слово, книга (подзаголовка нет, если книги нет) и счётчик `×N`. Толкование в строке не показывается: в статьях словарей оно бывает в HTML. `HistoryEntry.gloss` удалён.
