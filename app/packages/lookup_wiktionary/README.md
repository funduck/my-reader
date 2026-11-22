# lookup_wiktionary

Offline `LookupProvider` for the `en-en` pack (Wiktionary, CC BY-SA 4.0). Mode `enEn` only; `enRu` is StarDict's job.

```dart
final provider = WiktionaryLookupProvider(packStore: packStore, lemmas: lemmatizer);
final result = await provider.lookup(query);
provider.close(); // on shutdown
```

- The pack path comes from `PackStore.pathOf('en-en')`. The file is opened read-only with `package:sqlite3` on the first lookup and kept open.
- Pack not installed or unreadable: `ProviderUnavailable` with a reason. No entry: `LookupNotFound`.
- Lookup order: lemma candidates from the optional `lemmas` hook, then the normalized query text. The package does not lemmatize itself.
- Keys are normalized by `normalizeKey` (same rules as `normalize_key` in `service/build/schema.py`).
- Entries sharing a key (verb and noun, `Polish`/`polish`) are merged into one `LookupResult`, ordered by `rank`.

## SQLite

`package:sqlite3` uses the system SQLite: `app/pubspec.yaml` sets `hooks.user_defines.sqlite3.source: system`, so nothing is downloaded.

## Tests

`dart test` runs `lookupProviderContract` on the mini pack `service/fixtures/packs/en-en-20260101.1.sqlite` (read in place, not copied).

## Benchmark

100 random keys (fixed seed), warm provider, wall time of `lookup()` on the full pack `en-en-20261030.sqlite` (137 MB), Mac, 3 runs:

```
dart run benchmark/lookup_benchmark.dart <path to en-en pack>
```

| Run | p50 | p95 | max |
|---|---|---|---|
| 1 (cold OS file cache) | 0.50 ms | 1.17 ms | 1.76 ms |
| 2 | 0.07 ms | 0.24 ms | 0.58 ms |
| 3 | 0.05 ms | 0.23 ms | 0.58 ms |

First lookup including opening the file: 5-8 ms. Target p95 < 50 ms is met by a wide margin. The benchmark is not part of `check.sh`.
