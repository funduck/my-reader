# reader_simple

MVP-рендерер: `SimpleReaderEngine implements ReaderEngine` из `reader_api`. Рисует `ContentDocument` виджетами Flutter. Задача T-016, основа — вывод спайка `spikes/reader/REPORT.md`: `SelectableText` и `ScrollablePositionedList`.

## Как устроено

Глава — `ScrollablePositionedList.builder`, элементы строятся лениво.

| Элемент списка | Что |
|---|---|
| `0` | Кнопка «Previous chapter» (пустое место в первой главе) |
| `1..n` | Блоки главы: блок `i` — элемент `i + 1` |
| `n + 1` | Кнопка «Next chapter» (пустое место в последней главе) |

Блок рисует `BlockView`:

- абзац и заголовок — `SelectableText.rich` (курсив, жирный, ссылка подчёркнута; заголовки 1–6 — жирные, крупнее на 2,0 / 1,6 / 1,35 / 1,2 / 1,1 / 1,0 от размера шрифта);
- цитата — отступ и полоса слева, внутри блоки;
- список — маркер или номер и текст пункта;
- картинка — `Image.memory` по байтам из `OpenedBook.resource`; нет файла или битые байты — подпись `alt`.

`applySettings` меняет шрифт, размер, тему и отступы без перезагрузки: список остаётся тем же `State`, позиция прокрутки сохраняется.

Переход между главами: кнопка в конце списка открывает следующую главу с первого блока и шлёт `ChapterFinished`; кнопка в начале открывает предыдущую с её последнего блока. Ошибка чтения главы (`FormatException`) оставляет текущую главу и показывает «Could not open the chapter».

Позиция (T-017): первый видимый блок и строка превращаются в `Locator` (глава, `progression` по символам главы, `TextQuote` первой видимой строки, `engineHint` вида `simple:1:<глава>:<блок>:<смещение>`); `PositionChanged` не чаще раза в 500 мс. `load(at)` и `goTo` ищут место по `engineHint`, затем по `TextQuote`, затем по `progression`. `currentLocator()` отдаёт позицию сразу.

Тап и выделение (T-018): одиночный тап по слову шлёт `WordTapped` (слово без пунктуации, `Locator`, предложение) через 300 мс, если за это время не стало двойного клика. Кнопка «Translate» в меню выделения шлёт `TextSelected`. Предложение даёт `TextAnalyzer`, переданный в конструктор `SimpleReaderEngine`; он смотрит один абзац, не соседние. `highlight(ranges)` закрашивает диапазоны фоном.

## Пример

```
cd app/packages/reader_simple
flutter run -d macos -t example/main.dart
```

## Проверки

```
cd app && scripts/check.sh
```

Только пакет: `cd app/packages/reader_simple && flutter test`.

## Замер прокрутки

Тест: `integration_test/scroll_perf_test.dart`. Глава в 15 000 слов (150 абзацев по 100 слов) на `FakeOpenedBook`, 40 бросков вниз и 20 вверх внутри `binding.traceAction`. Сводка — `FrameTimingSummarizer` по `FrameTiming` каждого кадра (таймлайн `traceAction` в profile-режиме хранит только последние ~70 кадров, поэтому по нему вердикт не строится, см. отчёт спайка). Порог из отчёта спайка: 99-й процентиль build и raster не больше 16 мс. Тест также падает, если кадров меньше 1000 или список не прокрутился.

Запускает человек на Mac, в песочнице агента не работает:

```
cd app/packages/reader_simple
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/scroll_perf_test.dart --profile -d macos
```

Нужны права `com.apple.security.network.client` и `network.server` в `macos/Runner/DebugProfile.entitlements`: они уже включены.

### Результаты

Строки `FRAMES ...` из вывода команды.

| Метрика | build, мс | raster, мс |
|---|---|---|
| p99 | _заполнить_ | _заполнить_ |
| худший кадр | _заполнить_ | _заполнить_ |
| кадров всего / прокрутка, px | _заполнить_ | _заполнить_ |
| кадров дольше 16 мс | _заполнить_ | _заполнить_ |

Дата, Mac, версия Flutter: _заполнить_.

Для сравнения, спайк (тот же приём, 4984 кадра): p99 build 2,87 мс, raster 1,75 мс, худший 3,31 / 2,90 мс.
