# Решения: lookup_wiktionary

Контракты и соглашения пакета, принятые в задачах. Общие правила — в [docs/tasks/AGENT.md](../../../docs/tasks/AGENT.md#принятые-решения).

- `lookup_wiktionary` (T-044): `WiktionaryLookupProvider({packStore, lemmas, packId = 'en-en'})`, id `wiktionary.en-en`, только `enEn`. Нет пакета — `ProviderUnavailable`. Хук `lemmas` (`LemmaCandidates`) подключает лемматизатор `text_en`. Нужен `close()`. `normalizeKey` экспортируется и повторяет `normalize_key` сервиса. p95 на полном пакете — 0,2–1,2 мс.
