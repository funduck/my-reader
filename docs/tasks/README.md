# Задачи MVP

Задачи для агентов. Состав MVP и вехи — в [MVP-plan.md](../MVP-plan.md), там же диаграмма Ганта.

## Как работаем

Построчного ревью нет. Задачи ведёт **оркестратор** — одна сессия Claude. Человек проверяет приложение только в шести контрольных точках `U-1`…`U-6`.

Платформа MVP — macOS. Сборка, `integration_test` и контрольные точки — на Mac. Android — после MVP.

### Оркестратор

1. Запускает агента (Sonnet) на каждую задачу, у которой все зависимости `done`. Каждый агент — в своём worktree, на ветке `task/<id>`. Одновременно — до 6 агентов.
2. Следит, чтобы каждый пункт «Готово, когда» проверялся командой или тестом. Ручные проверки — только в `U-*`. Принимает результат, только если: `app/scripts/check.sh` или `uv run pytest` зелёный; изменены только пути из «Где»; выполнены все пункты «Готово, когда». Сам перезапускает проверки и читает тесты: зелёный тест с широким допуском может прятать ошибку.
3. Не принял — возвращает агенту с конкретным замечанием. После второй неудачи дробит задачу на меньшие или останавливается и пишет человеку.
4. Принятую ветку вливает в `main` и ставит в файле задачи `**Статус:** done`. Конфликты в `bootstrap.dart` разрешает сам, сохраняя обе правки.
5. Когда закрыты зависимости контрольной точки, собирает `flutter build macos` и зовёт человека. Код при этом не ждёт: оркестратор продолжает независимые задачи.
6. Замечания человека из контрольной точки оформляет новыми задачами `T-1xx` в этой папке.
7. Команды, которые в песочнице не работают (см. «Окружение»), передаёт человеку готовой строкой и ждёт результата.
8. Отчёты-документы (`REPORT.md` и подобные) агент возвращает текстом, файл сохраняет оркестратор.
9. Решения из раздела отчёта «Решения для оркестратора» переносит в «Принятые решения» или возвращает агенту.
10. Не даёт агенту указаний в обход отказа инструмента или песочницы. Такой отказ — вопрос к человеку.

### Агент

1. Прочитать `CLAUDE.md`, файл задачи и разделы из «Прочитать».
2. Трогать только пути из «Где». Нужно больше или задача не помещается — остановиться и написать оркестратору, что мешает.
3. Тесты обязательны. Перед сдачей — `app/scripts/check.sh` или `uv run pytest` в `service/`.
4. `app/app/lib/bootstrap.dart` правят только задачи с пометкой об этом в разделе «Важно».
5. **Проблема окружения — стоп, а не обход.** Нет сети, отказ песочницы, нет прав, нет инструмента, зависла команда, одна и та же ошибка второй раз — остановиться и написать оркестратору текст ошибки и команду. Не поднимать свои серверы, не класть файлы вручную в общие кэши (`~/.pub-cache` и т. п.), не искать по всему диску, не трогать системные настройки и сертификаты.
6. Не запускать то, что в песочнице не работает (см. «Окружение»). Написать в отчёте точную команду для человека.
7. Тест проверяет пункт «Готово, когда» ровно. Не расширять допуск и не ослаблять проверку, чтобы тест прошёл. Не получилось — так и написать в отчёте.
8. Не коммитить непроверенное. Проверки не запустились — работа остаётся незакоммиченной, в отчёте сказано почему.
9. Отказ инструмента не обходить другим инструментом. Отчёт-документ вернуть текстом в ответе.
10. Отчёт оркестратору:
    - что проверено тестом или командой, что написано, но не проверено, что только описано;
    - точные команды и их результат;
    - раздел «Решения для оркестратора»: всё, что выбрано самостоятельно и касается других задач (контракты, схемы, зависимости, импорты, соглашения в коде).

### Окружение

Агенты работают в песочнице. Что в ней есть:

- Flutter 3.50.1 / Dart 3.14 и `uv` работают: `pub get`, `dart analyze`, `dart test`, `flutter test`, `uv run pytest`.
- Сеть: только pub.dev, storage.googleapis.com, pypi.org, files.pythonhosted.org. Отказ запроса к google-analytics.com — телеметрия Flutter, его не замечать.

Что в песочнице **не работает** и делается человеком на Mac:

- `flutter build macos`, `flutter run -d macos`, `flutter drive -d macos`, интеграционные тесты на macOS: Xcode не может писать в `~/Library`.
- Всё, что требует окна, мыши или глаз.

Для `integration_test` с `traceAction` на macOS в `macos/Runner/DebugProfile.entitlements` нужно `com.apple.security.network.client`: приложение подключается к своему VM service.

### Контрольные точки

| Точка | Когда | Что проверяешь на Mac |
|---|---|---|
| [U-1](U-1.md) | Готова читалка | Импорт книги, чтение, позиция после перезапуска |
| [U-2](U-2.md) | Готов сервис | Пакеты собираются, размер `en-en` приемлем |
| [U-3](U-3.md) | Готово толкование | Тап по слову без сети, скорость, запись в историю |
| [U-4](U-4.md) | Готова разминка | Слова в разминке действительно незнакомые; подстройка порогов |
| [U-5](U-5.md) | Готов StarDict | Свой словарь, переключение EN→EN / EN→RU |
| [U-6](U-6.md) | Готово всё | Неделя ежедневного чтения |

Если в точке найдено что-то, что ломает дальнейшую работу, — говоришь оркестратору «стоп».

## Принятые решения

Чтобы агенту не приходилось выбирать самому:

- Pub workspaces без melos.
- Доменные классы в `core` — ручной код (`==`, `hashCode`, `copyWith`), без `freezed` и кодогенерации. Классы с ручным `==` помечаются `@immutable` из `package:meta` (зависимость `core`): этого требует линт `avoid_equals_and_hash_code_on_mutable_classes`.
- Вид пакета задаёт каталог (проверяет `app/tool/check_imports.dart`): `packages/core`, `packages/core_testing`, `packages/reader_api`, `packages/reader_*` — рендереры (от `core` и `reader_api`), `packages/features/common` — `features_common` (от `core` и `reader_api`), `packages/features/<name>` — фичи (от `core`, `reader_api`, `features_common`; друг от друга — нет), остальное в `packages/` — адаптеры.
- `TextQuote`: точная цитата плюс до 30 символов до и после, пробелы схлопнуты в один.
- Условная страница для шпаргалки — 300 слов.
- Riverpod, `go_router`, drift для базы приложения, `package:sqlite3` для чтения пакетов, `package:http`.
- Сервис: Python 3.12, `uv`, `ruff`, `pytest`.
- Виджеты Material — из `package:material_ui/material_ui.dart`: в Flutter 3.50 `package:flutter/material.dart` устарел, и `--fatal-infos` на нём падает.
- Конструкторы — в форме Dart 3.14 `const new(...)`: этого требует линт `unnecessary_type_name_in_constructor`. Именованные фабрики — `factory fromJson(...)` без имени типа; вызов снаружи прежний: `Locator.fromJson(...)`.
- Доменные типы импортируются из `package:core/domain_books.dart` и `package:core/domain_lookup.dart`; `core.dart` их не реэкспортирует. Внутри `core/lib` — относительными путями.
- `TextQuote.fromText` бросает `RangeError` при `start >= end` или выходе за границы; контекст считается после схлопывания пробелов.
- `CefrLevel.unknown` вне порядка: все сравнения с ним `false`, `compareTo` бросает `StateError`. Фильтр «выше уровня пользователя» — `level.isHarderThan(profile.level)`.
- `UserProfile.providerOrder` пустой — значит порядок регистрации провайдеров.
- Порты (`package:core/ports.dart`): `LookupProvider.lookup` при неудаче бросает `ProviderUnavailable` или `LookupNotFound` (sealed `LookupFailure`), цепочка идёт к следующему провайдеру; отмена — `CancelledException` через `CancelToken`. `BookFormatAdapter` принимает абсолютный путь `String path`, на битый файл бросает `FormatException`. `TextAnalyzer` и `LevelDictionary` синхронные, офсеты — UTF-16, полуинтервал.

- `reader_api` (T-015): `ReaderEngine` (`buildView`, `load(book, {at})`, `goTo`, `applySettings`, `highlight(List<Locator>)` заменяет прежний набор, `events` — broadcast, `dispose` один раз). `load` не закрывает `OpenedBook`. `ReaderSettings`: `fontFamily` (null — шрифт движка), `fontSize` = 18, `theme` (`ReaderTheme.light/dark`), `horizontalPadding` = 16; расширять только аддитивно.

- `text_en` (T-042): токен — буквы и цифры, хотя бы одна буква. Апостроф между буквами внутри токена (`don't`, `James's` — один токен), дефис между буквами и цифрами тоже (`well-known`). Точки в токены не входят (`Mr.` → `Mr`). Временная лемма — lowercase плюс `’`/`ʼ` → `'`.

- `packs_http` (T-040): `HttpPackStore({baseUri, directory, client?, timeout})`. Файлы `<dir>/<id>.sqlite` и `<dir>/packs.json` (`{"packs": {id: version}}`). Ошибки — sealed `PackException`: `PackNetworkException`, `PackHashMismatchException`, `PackManifestException`, `PackNotFoundException`. Докачки и отмены нет.

- Провайдеры портов (T-009) — в `packages/features/common` (`package:features_common/features_common.dart`), все `Provider<T>`; без override бросают `PortNotWiredError`. Фича зависит от `features_common` и `flutter_riverpod`, другие фичи и `app` не импортирует; в тестах — `xProvider.overrideWithValue(fake)`. Новые порты — через `_port<T>(name)` в `port_providers.dart`. Маршруты — константы `Routes` в `app/app/lib/router.dart`; фичи заменяют `builder` заглушки там же. `Override` и `ProviderException` импортируются из `package:flutter_riverpod/misc.dart`.

- `format_epub` (T-010): `ChapterRef.href` — путь записи внутри контейнера (`OEBPS/text/ch1.xhtml`), уже разрешённый относительно OPF; `index` — позиция в spine, `linear="no"` включается. Обложка — через `EpubFormatAdapter.readCover(path)` и `EpubBook.cover()`, в `BookMetadata` её нет. Для ссылок из nav/NCX/XHTML — `resolveEntryPath(base, href)`.

- `core_testing` (T-006): контрактные наборы лежат в `lib/` (`test` — обычная зависимость), адаптеры подключают `core_testing` в `dev_dependencies`. Фабрика во всех наборах — `FutureOr<T> Function() create`, вызывается в `setUp`, возвращает свежий пустой объект. Журнал: фильтр по книге и главе — по `event.query.locator`, `from` включительно, `to` исключительно, порядок «новые сначала»; фильтр по уровню контракт не проверяет (решает T-008). Потоки `watch*` сразу отдают текущее значение. Каскад «удалить книгу — удалить прогресс» проверяет T-007, не контракт.

- SQLite (`package:sqlite3`, drift): системная библиотека ОС. В `app/pubspec.yaml` задано `hooks: user_defines: sqlite3: source: system`, чтобы build hook не качал бинарник с github.com. Для Android пересмотреть после MVP. Открытие пакетов — `sqlite3.open(path, mode: OpenMode.readOnly)`; строка результата — `row.columnAt(i)`.

- Оглавление EPUB (T-011): `TocEntry.chapter.href` — `путь#фрагмент` (фрагмент как в источнике, без отдельного поля), `index` — позиция файла в spine; несколько пунктов могут делить один `index`. Пункты вне spine и внешние ссылки отбрасываются, их дети поднимаются. Источник: nav → NCX → по пункту на spine.
- XHTML → `ContentDocument` (T-012): `convertXhtml(xhtml, path:)` → `ChapterContent(document, anchors)`. В `ContentDocument` нет id элементов, поэтому `anchors` — побочная таблица id → индекс верхнего блока. Внутренние ссылки — `путь#фрагмент`, картинки — путь записи. Вложенные списки уплощаются, картинка внутри абзаца режет его на части.
- Толкование (T-045, `package:core/application.dart`): `ProviderChain.lookup` → sealed `ChainResult` (`ChainSuccess` / `ChainFailure`), таймаут 5 с на провайдера. `LookupSelection.call` → sealed `LookupOutcome` (`LookupAnswered` / `LookupUnanswered`, у второго `isNotFound`). Сбой провайдеров — значение, бросается только `CancelledException` (тогда ничего не пишется). Порядок: id из `providerOrder` первыми, остальные — в порядке регистрации. Событие и `Term` пишутся и при неудаче. Провайдеру уходит исходный текст; лемму `WiktionaryLookupProvider` берёт через свой хук `lemmas`, `LookupQuery` не меняется.
- Общие файлы, которые задача правит только добавлением строк, перечисляются в «Где» с пометкой: `app/pubspec.yaml` (workspace — для нового пакета), `app/app/pubspec.yaml` (зависимости — для проводки в `bootstrap.dart`), `app/app/lib/router.dart` (замена `builder` заглушки своего маршрута), `core/lib/application.dart` (экспорт сценария). Конфликты в них разрешает оркестратор.
- Каталоги приложения на устройстве — через `path_provider` (`getApplicationSupportDirectory()`), только в `app/app`. Адрес сервиса — `UserProfile.serviceUrl` (null — `http://localhost:8080`).
- `core` не может зависеть от `core_testing` (правило `check_imports`), поэтому тесты `core/application` держат свои мелкие фейки в `core/test/`.
- `reader_simple` (T-016): `ScrollablePositionedList`, элемент 0 — «Previous chapter», блок `i` — элемент `i + 1`, последний — «Next chapter». Состояние — `engine.chapter` (`ValueListenable<ChapterState?>`) и `engine.style`. Тап и выделение подключаются в `BlockView`. `ChapterFinished` уходит по кнопке «Next chapter».

- `storage_drift` (T-007): `openDatabase(path)` / `openInMemory()` → `AppDatabase` с геттерами `bookRepository`, `progressRepository`, `profileRepository`. `Locator` и `UserProfile` — JSON-текст, `DateTime` — микросекунды UTC. FK нет, каскад прогресса — в `remove`. `*.g.dart` коммитятся (`dart run build_runner build`). Новая таблица: `tables.dart` → `@DriftDatabase` → поднять `currentSchemaVersion` и `onUpgrade` → `drift_dev schema dump` → `schema generate` в `test/generated` с переименованием выхода в `*.g.dart` (иначе `strict_raw_type` в сгенерированном коде) → тест миграции в `schema_test.dart`.
- `lookup_wiktionary` (T-044): `WiktionaryLookupProvider({packStore, lemmas, packId = 'en-en'})`, id `wiktionary.en-en`, только `enEn`. Нет пакета — `ProviderUnavailable`. Хук `lemmas` (`LemmaCandidates`) подключает лемматизатор `text_en`. Нужен `close()`. `normalizeKey` экспортируется и повторяет `normalize_key` сервиса. p95 на полном пакете — 0,2–1,2 мс.

- `levels_cefr` (T-050): `CefrLevelDictionary.open(PackStore)` (нет пакета — `empty()`, всегда `unknown`), `.fromPath(path)`, `close()`. Пакет проверяется один раз при `open`: после загрузки `en-levels` словарь открыть заново. С POS — строки с этим POS и `any`, иначе все; побеждает самый лёгкий известный уровень. Лемму приводит вызывающий.

- Лемматизация (T-043): `FormsLemmatizer.open(path)` реализует `Lemmatizer`, подключается как `EnglishTextAnalyzer(lemmatizer: ...)`; без него — прежний lowercase. Фильтр по `pos` строгий. Для `don't`, `James's`: сначала токен целиком, затем исключения (`can't` → can), затем основа без клитика, только если она есть в таблице. Для слов с дефисом лемматизируется последняя часть. Кэш LRU на 1000 запросов; закрывает владелец.
- Кусок для шпаргалки (T-052): `selectCheatSheetRange(book, from:, scope:)` → `CheatSheetRange?` (`start`, `end`, `text`, `wordCount`); `null` — нечего анализировать. Абзацы и главы склеиваются через `'\n\n'`, офсеты анализатора — относительно `text`. Слово — `[\p{L}\p{N}]+`, склейка через апостроф и дефис (`countWords`). Абзац, добивший бюджет, входит целиком. Абзац по `from` ищется только по `progression` (quote не используется) — если рендерер считает progression иначе, возможен сдвиг на соседний абзац.
- StarDict, формат (T-060): `StarDictInfo.parse`, `StarDictIndex.parse/open(path, info)`, `index.lookup(word)` → `List<StarDictEntry>` (точное написание первым). `.idx` целиком в памяти, сортировка не проверяется. Генератор фикстур — `test/fixtures/build.dart` (`buildStarDict`), импортировать относительным путём.

- StarDict, статьи (T-061): `decompressDictDz(dzPath, dictPath)` — один раз при импорте, хранится только `.dict` (битый gzip → `FormatException`, частичный файл удаляется). `StarDictDict.open(path, info)` синхронный, нужен `close()`; `read(entry)` → `StarDictArticle` (`fields: List<StarDictField(type, text)>`, `text` — через `\n`). `h` отдаётся сырым HTML, `x` — без тегов (без разделителя между тегами), бинарные типы пропускаются. Настоящий dictzip с таблицей чанков не проверен.
- Шпаргалка (T-053): `BuildCheatSheet({generator, profiles, terms})`, `call(book, {from, cancel})` → `CheatSheet?`. `LevelCheatSheetGenerator({analyzer, levels})`: `text` элемента — лемма, `example` — первое предложение куска с ней, `translation` пустой. `unknown` отбрасывается. Ранжирование: уровень ↓, Zipf ↑ (нет Zipf — самое редкое), число в куске ↓, первое вхождение ↑. Имя собственное — ни разу строчной и с заглавной не в начале предложения. Выученные леммы — `terms.watchAll().first`, любой статус. Константы — `cheat_sheet_config.dart` (`cheatSheetMaxItems = 15`).
- Модалка (T-046): `showLookupSheet(context, query, {onOpenSettings})` из `package:lookup_sheet/lookup_sheet.dart`; про go_router не знает — вызывающий передаёт `() => context.go(Routes.settings)`. `lookupSelectionProvider` собирается в фиче из портов `features_common`, в bootstrap подключаются только порты. Переключатель EN→RU/EN→EN в шапке — только для открытого окна, в профиль не пишется. Любой `LookupUnanswered` с `!isNotFound` — «нет словаря» с кнопкой в настройки. Тексты без l10n.
- Журнал и термины (T-008): порты `core` не менялись (`record`/`get`/`watch(filter)`, `find`/`watchAll`/`save`). `AppDatabase.lookupJournal` → `DriftLookupJournal` (+`byTerm`), `AppDatabase.termRepository` → `DriftTermRepository` (+`upsert` в транзакции, `byLemma`, `allLemmas({language, status})` — все статусы, если `status` не задан). `LookupSelection` (T-045) пока делает `find` + `save`, а не `upsert`. Схема v2: `lookup_events`, `terms` (уникальный `(normalized, language)`), `term_events` (`position` — порядок `eventIds`). Журнал — `at` ↓, затем `rowid` ↓.
- Библиотека (T-019): `ImportBook({adapters, books, clock, ids, directory, hash})`, `call(path)` → sealed `ImportOutcome` (`BookImported` / `BookAlreadyImported` / `BookUnsupported`); бросается только `FileSystemException`. Файл — `<directory>/<hash>.<format>`, хеш внедряется (`sha256OfFile` в `features_library`). `main.dart` асинхронный: `bootstrap(overrides: [...buildOverrides(), ...await buildDeviceOverrides()])`; `buildDeviceOverrides` открывает drift в `<applicationSupport>/my_reader.sqlite` и подключает репозитории, `EpubFormatAdapter`, `booksDirectoryProvider` (`<applicationSupport>/books`). Новые устройство-зависимые порты добавляются туда же. `LibraryScreen({onOpenBook})` — навигацию делает `router.dart`.

## Волны

Задачи одной волны можно запускать параллельно: их зависимости закрыты предыдущими волнами. Номер волны — самый ранний старт при неограниченном числе агентов.

| Волна | Задачи |
|---|---|
| 1 | [T-001](T-001.md), [T-021](T-021.md), [T-030](T-030.md) |
| 2 | [T-002](T-002.md), [T-003](T-003.md), [T-004](T-004.md), [T-031](T-031.md), [T-034](T-034.md) |
| 3 | [T-005](T-005.md), [T-032](T-032.md), [T-033](T-033.md), [T-035](T-035.md) |
| 4 | [T-006](T-006.md), [T-009](T-009.md), [T-010](T-010.md), [T-015](T-015.md), [T-040](T-040.md), [T-042](T-042.md) |
| 5 | [T-007](T-007.md), [T-011](T-011.md), [T-012](T-012.md), [T-016](T-016.md), [T-036](T-036.md), [T-043](T-043.md), [T-044](T-044.md), [T-045](T-045.md), [T-050](T-050.md), [T-052](T-052.md), [T-060](T-060.md) |
| 6 | [T-008](T-008.md), [T-019](T-019.md), [T-041](T-041.md), [T-046](T-046.md), [T-053](T-053.md), [T-061](T-061.md) |
| 7 | [T-013](T-013.md), [T-017](T-017.md), [T-051](T-051.md), [T-062](T-062.md), [T-070](T-070.md) |
| 8 | [T-014](T-014.md), [T-018](T-018.md), [T-020](T-020.md) |
| 9 | [T-047](T-047.md), [T-054](T-054.md), [T-071](T-071.md) |
| 10 | [T-048](T-048.md), [T-055](T-055.md), [T-063](T-063.md) |

## Все задачи

| ID | Задача | Веха | Поток | Зависит от | Дней |
|---|---|---|---|---|---|
| [T-001](T-001.md) | Каркас монорепозитория app/ | M0 | Каркас и ядро | — | 1 |
| [T-002](T-002.md) | Проверка правил импорта и скрипт check | M0 | Каркас и ядро | T-001 | 1 |
| [T-003](T-003.md) | Доменная модель: книги и чтение | M0 | Каркас и ядро | T-001 | 1 |
| [T-004](T-004.md) | Доменная модель: толкование, история, профиль, шпаргалка | M0 | Каркас и ядро | T-001 | 1 |
| [T-005](T-005.md) | Порты ядра | M0 | Каркас и ядро | T-003, T-004 | 1 |
| [T-006](T-006.md) | core_testing: фейки и контрактные тесты | M0 | Каркас и ядро | T-005 | 1 |
| [T-007](T-007.md) | storage_drift: книги, прогресс, профиль | M0 | Каркас и ядро | T-006 | 1 |
| [T-008](T-008.md) | storage_drift: журнал запросов и термины | M3 | Каркас и ядро | T-007 | 1 |
| [T-009](T-009.md) | app: bootstrap, роутинг, тема | M0 | Каркас и ядро | T-005 | 1 |
| [T-010](T-010.md) | format_epub: контейнер, OPF, метаданные, spine | M1 | Читалка | T-005 | 1 |
| [T-011](T-011.md) | format_epub: оглавление nav.xhtml и toc.ncx | M1 | Читалка | T-010 | 1 |
| [T-012](T-012.md) | format_epub: XHTML → ContentDocument | M1 | Читалка | T-010 | 2 |
| [T-013](T-013.md) | format_epub: главы по оглавлению, а не по файлам | M1 | Читалка | T-011, T-012 | 1 |
| [T-014](T-014.md) | format_epub: контрактный тест и кривые файлы | M1 | Читалка | T-013, T-006 | 1 |
| [T-015](T-015.md) | reader_api: контракт рендерера | M1 | Читалка | T-005 | 1 |
| [T-016](T-016.md) | reader_simple: отрисовка ContentDocument | M1 | Читалка | T-015, T-021 | 2 |
| [T-017](T-017.md) | reader_simple: позиция ↔ Locator | M1 | Читалка | T-016 | 1 |
| [T-018](T-018.md) | reader_simple: тап по слову и выделение | M1 | Читалка | T-017 | 1 |
| [T-019](T-019.md) | features/library: импорт и список книг | M1 | Читалка | T-007, T-009, T-010 | 1 |
| [T-020](T-020.md) | features/reader: экран чтения | M1 | Читалка | T-019, T-017, T-013 | 1 |
| [T-021](T-021.md) | Спайк рендерера: SelectableText, тап, позиция | M1 | Читалка | — | 1 |
| [T-030](T-030.md) | Сервис: каркас и схемы пакетов | M2 | Сервис | — | 1 |
| [T-031](T-031.md) | Сервис: загрузка и чтение дампа kaikki.org | M2 | Сервис | T-030 | 1 |
| [T-032](T-032.md) | Сервис: пакет en-en | M2 | Сервис | T-031 | 2 |
| [T-033](T-033.md) | Сервис: пакет en-forms | M2 | Сервис | T-031 | 1 |
| [T-034](T-034.md) | Сервис: пакет en-levels | M2 | Сервис | T-030 | 1 |
| [T-035](T-035.md) | Сервис: пороги Zipf → CEFR | M2 | Сервис | T-034 | 1 |
| [T-036](T-036.md) | Сервис: manifest и раздача по HTTP | M2 | Сервис | T-032, T-033, T-035 | 1 |
| [T-040](T-040.md) | packs_http: загрузка пакетов | M3 | Толкование | T-005, T-030 | 1 |
| [T-041](T-041.md) | features/settings: настройки и загрузка пакетов | M3 | Толкование | T-040, T-009, T-007 | 1 |
| [T-042](T-042.md) | text_en: предложения и токены | M3 | Толкование | T-005 | 1 |
| [T-043](T-043.md) | text_en: лемматизация по en-forms | M3 | Толкование | T-042, T-030 | 1 |
| [T-044](T-044.md) | lookup_wiktionary: провайдер en-en | M3 | Толкование | T-006, T-030 | 1 |
| [T-045](T-045.md) | core: ProviderChain и LookupSelection | M3 | Толкование | T-006 | 1 |
| [T-046](T-046.md) | features/lookup_sheet: модалка | M3 | Толкование | T-045, T-009 | 1 |
| [T-047](T-047.md) | Проводка: тап в читалке → толкование → история | M3 | Толкование | T-020, T-018, T-046, T-044, T-043, T-008, T-041 | 1 |
| [T-048](T-048.md) | Сквозной тест толкования и замер задержки | M3 | Толкование | T-047 | 1 |
| [T-050](T-050.md) | levels_cefr: уровни слов | M4 | Разминка | T-006, T-030 | 1 |
| [T-051](T-051.md) | lookup_sheet: показать уровень слова | M4 | Разминка | T-050, T-046 | 1 |
| [T-052](T-052.md) | core: выбор куска текста для шпаргалки | M4 | Разминка | T-006 | 1 |
| [T-053](T-053.md) | core: генератор шпаргалки и BuildCheatSheet | M4 | Разминка | T-052 | 1 |
| [T-054](T-054.md) | features/cheatsheet: экран разминки | M4 | Разминка | T-053, T-046, T-020 | 1 |
| [T-055](T-055.md) | Связка разминки | M4 | Разминка | T-054, T-050, T-047, T-051 | 1 |
| [T-060](T-060.md) | lookup_stardict: .ifo и .idx | M5 | StarDict | T-006 | 1 |
| [T-061](T-061.md) | lookup_stardict: .dict и .dict.dz | M5 | StarDict | T-060 | 1 |
| [T-062](T-062.md) | lookup_stardict: провайдер и импорт | M5 | StarDict | T-061 | 1 |
| [T-063](T-063.md) | UI: StarDict, режим и порядок провайдеров | M5 | StarDict | T-062, T-047, T-041 | 1 |
| [T-070](T-070.md) | features/history: список запросов | M6 | История | T-008, T-009 | 1 |
| [T-071](T-071.md) | Переход из истории к месту в книге | M6 | История | T-070, T-020 | 1 |
| [U-1](U-1.md) | Проверка M1: читалка | M1 | Контрольные точки | T-020 | 0 |
| [U-2](U-2.md) | Проверка M2: сервис и пакеты | M2 | Контрольные точки | T-036 | 0 |
| [U-3](U-3.md) | Проверка M3: толкование офлайн | M3 | Контрольные точки | T-048, U-2 | 0 |
| [U-4](U-4.md) | Настройка разминки на реальной книге | M4 | Контрольные точки | T-055, U-3 | 1 |
| [U-5](U-5.md) | Проверка M5: свой StarDict | M5 | Контрольные точки | T-063 | 0 |
| [U-6](U-6.md) | Неделя ежедневного чтения | M6 | Контрольные точки | T-071, U-4, U-5 | 7 |
