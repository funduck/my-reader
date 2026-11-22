# Решения: features/history

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/README.md](../../../../docs/tasks/README.md#принятые-решения).

- История (T-070): `HistoryScreen({onOpenLocation})` из `package:features_history/features_history.dart`; колбэк получает `event.query.locator` строки контекста, без колбэка строки не нажимаются. `historyProvider(BookId?)` собирает термины, весь журнал и книги в памяти; фильтр по книге — локальное состояние экрана, `LookupFilter` не используется. `lookupJournalProvider` и `termRepositoryProvider` проведены в `buildDeviceOverrides`.
