# Правила для агента

Агент делает одну задачу из этой папки. Как устроена работа целиком и что делает оркестратор — в [README.md](README.md).

## Работа

1. Прочитать этот файл, файл задачи, `DECISIONS.md` пакетов из «Где» и пакетов, чей API используется. Из `docs/` — только разделы из «Прочитать», не файлы целиком. Остальное — по коду.
   Код читать точечно: `grep -n`, затем `sed -n <от>,<до>p` нужной функции. Файлы целиком (`cat`) — только свои и короткие. Не перечитывать то, что уже прочитано.
2. Трогать только пути из «Где». Нужно больше или задача не помещается — остановиться и написать оркестратору, что мешает.
3. Тесты обязательны. Во время работы — `app/scripts/check.sh --package <путь пакета>` (только свой пакет). Перед сдачей — один полный `app/scripts/check.sh` или `uv run pytest` в `service/`. Вывод — в свой файл `$TMPDIR/check-<id>.log`, читать хвост и ошибки, а не весь лог.
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

## Окружение

Агенты работают в песочнице. Что в ней есть:

- Flutter 3.50.1 / Dart 3.14 и `uv` работают: `pub get`, `dart analyze`, `dart test`, `flutter test`, `uv run pytest`.
- Сеть: только pub.dev, storage.googleapis.com, pypi.org, files.pythonhosted.org.

Что в песочнице **не работает** и делается человеком на Mac:

- `flutter build macos`, `flutter run -d macos`, `flutter drive -d macos`, интеграционные тесты на macOS: Xcode не может писать в `~/Library`.
- Всё, что требует окна, мыши или глаз.

Для `integration_test` с `traceAction` на macOS в `macos/Runner/DebugProfile.entitlements` нужно `com.apple.security.network.client`: приложение подключается к своему VM service.

## Принятые решения

Чтобы агенту не приходилось выбирать самому. Здесь — только общие правила. Контракты и соглашения пакета — в его `DECISIONS.md`: `app/packages/<пакет>/DECISIONS.md`, проводка приложения — `app/app/DECISIONS.md`. Агент читает `DECISIONS.md` пакетов из «Где» и пакетов, чей API использует, а не все.

- Pub workspaces без melos.
- Доменные классы в `core` — ручной код (`==`, `hashCode`, `copyWith`), без `freezed` и кодогенерации. Классы с ручным `==` помечаются `@immutable` из `package:meta` (зависимость `core`): этого требует линт `avoid_equals_and_hash_code_on_mutable_classes`.
- Вид пакета задаёт каталог (проверяет `app/tool/check_imports.dart`): `packages/core`, `packages/core_testing`, `packages/reader_api`, `packages/reader_*` — рендереры (от `core` и `reader_api`), `packages/features/common` — `features_common` (от `core` и `reader_api`), `packages/features/<name>` — фичи (от `core`, `reader_api`, `features_common`; друг от друга — нет), остальное в `packages/` — адаптеры.
- Условная страница для шпаргалки — 300 слов.
- Riverpod, `go_router`, drift для базы приложения, `package:sqlite3` для чтения пакетов, `package:http`.
- Сервис: Python 3.12, `uv`, `ruff`, `pytest`.
- Виджеты Material — из `package:material_ui/material_ui.dart`: в Flutter 3.50 `package:flutter/material.dart` устарел, и `--fatal-infos` на нём падает.
- Конструкторы — в форме Dart 3.14 `const new(...)`: этого требует линт `unnecessary_type_name_in_constructor`. Именованные фабрики — `factory fromJson(...)` без имени типа; вызов снаружи прежний: `Locator.fromJson(...)`.
- Доменные типы импортируются из `package:core/domain_books.dart` и `package:core/domain_lookup.dart`; `core.dart` их не реэкспортирует. Внутри `core/lib` — относительными путями.
- Провайдеры портов (T-009) — в `packages/features/common` (`package:features_common/features_common.dart`), все `Provider<T>`; без override бросают `PortNotWiredError`. Фича зависит от `features_common` и `flutter_riverpod`, другие фичи и `app` не импортирует; в тестах — `xProvider.overrideWithValue(fake)`. Новые порты — через `_port<T>(name)` в `port_providers.dart`. Маршруты — константы `Routes` в `app/app/lib/router.dart`; фичи заменяют `builder` заглушки там же. `Override` и `ProviderException` импортируются из `package:flutter_riverpod/misc.dart`.
- SQLite (`package:sqlite3`, drift): системная библиотека ОС. В `app/pubspec.yaml` задано `hooks: user_defines: sqlite3: source: system`, чтобы build hook не качал бинарник с github.com. Для Android пересмотреть после MVP. Открытие пакетов — `sqlite3.open(path, mode: OpenMode.readOnly)`; строка результата — `row.columnAt(i)`.
- Общие файлы, которые задача правит только добавлением строк, перечисляются в «Где» с пометкой: `app/pubspec.yaml` (workspace — для нового пакета), `app/app/pubspec.yaml` (зависимости — для проводки в `bootstrap.dart`), `app/app/lib/router.dart` (замена `builder` заглушки своего маршрута), `core/lib/application.dart` (экспорт сценария). Конфликты в них разрешает оркестратор.
- Каталоги приложения на устройстве — через `path_provider` (`getApplicationSupportDirectory()`), только в `app/app`. Адрес сервиса — `UserProfile.serviceUrl` (null — `http://localhost:8080`).
- Логи — `package:logging` в любом пакете, включая `core`: `final Logger _log = Logger('<ИмяКласса>')`. `fine` — подробности, `info` — шаги сценария, `warning` — ожидаемый сбой (сеть, плохой файл), `severe` — баг. В `catch` пишется ошибка и стек. Не логировать тексты книг целиком и ключи API. Вывод настраивает только `app/app/lib/logging.dart` (`setUpLogging` в `main`): консоль и файл `<applicationSupport>/logs/app.log` (больше 1 МБ на старте — в `app.log.1`), в debug — всё, в release — от `INFO`. Там же `LoggingProviderObserver` (упавшие провайдеры) и перехват необработанных ошибок; навигацию пишет go_router (`debugLogDiagnostics`).
- `core` не может зависеть от `core_testing` (правило `check_imports`), поэтому тесты `core/application` держат свои мелкие фейки в `core/test/`.
