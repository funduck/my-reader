# Спайк рендерера: SelectableText (T-021)

## Итог

**Предварительно оставляем `SelectableText`.** Тап по слову, позиция и своя кнопка в меню работают на штатных API, это подтверждено тестами. Вывод держится, пока нет замера прокрутки (пункт 3). Если p99 кадра в profile-режиме больше 16 мс, переходим на `TextPainter`.

| Пункт | Состояние |
|---|---|
| 1. Тап по слову, мышь, двойной клик | Работает, проверено тестами |
| 2. Первый видимый блок и возврат | Работает с точностью до строки, проверено тестами |
| 3. Время кадра при прокрутке | **Не замерено**, харнесс готов, нужен запуск на Mac |
| 4. Своя кнопка в контекстном меню | Работает, проверено тестом |

Проверено: `flutter analyze` без замечаний, `flutter test` 6 из 6. Тесты виджетные, без реального окна и мыши. Что нужно подтвердить руками, сказано в конце.

## Текст

`lib/text_gen.dart` собирает главу около 15 000 слов (около 150 абзацев) из фиксированных фраз детерминированным генератором. Это **не книга из public domain**, как требовала задача: в песочнице агента сеть открыта только до pub.dev. Текст однообразный, но длина слов, предложений и абзацев близка к прозе. Для вёрстки и прокрутки этого хватает. Если на замере что-то покажется подозрительным, повторить его на настоящей главе.

## 1. Тап по слову

`SelectableText.onTap` не даёт координат. Приём:

1. Обернуть абзац в `Listener` и запоминать `event.position` в `onPointerDown`. `Listener` не участвует в арене жестов, поэтому выделение не ломается.
2. В `onTap` найти `RenderEditable` абзаца и взять символ под точкой: `getPositionForPoint(globalPoint).offset`.
3. Слово взять своей регуляркой по тексту абзаца, а не `getWordBoundary`. Так мы сами решаем, что делать с апострофами и дефисами.

```dart
Listener(
  onPointerDown: (e) => _lastDown = e.position,
  child: SelectableText.rich(
    TextSpan(text: paragraph),
    key: key, // GlobalKey
    onTap: () {
      final off = findRenderEditable(key.currentContext!)
          ?.getPositionForPoint(_lastDown)
          .offset;
      final r = off == null ? null : wordRangeAt(paragraph, off);
      // r.textInside(paragraph) — слово; (блок, r.start) — Locator
    },
  ),
)
```

`findRenderEditable` обходит дерево рендера под `SelectableText` и находит `RenderEditable`. Код в `lib/word_at.dart`.

**Двойной клик.** Двойной клик штатно выделяет слово. Но `onTap` срабатывает и на первом клике, поэтому без мер перевод открылся бы дважды. Решение: отправлять тап с задержкой 300 мс (`kDoubleTapTimeout`) и отменять его, если `onSelectionChanged` пришёл с непустым выделением. Цена: перевод по одиночному тапу открывается на 300 мс позже. Для T-016 стоит проверить на руках, не раздражает ли это. Можно сократить задержку или открывать модалку сразу и закрывать при двойном клике.

Тесты: тап в начале главы, тап после прокрутки к блоку 50, двойной клик выделяет одно слово и не даёт тапа.

## 2. Первый видимый блок и возврат

Список: `ScrollablePositionedList` из пакета `scrollable_positioned_list`.

**Первый видимый блок.** Из `itemPositions` взять элементы с `itemTrailingEdge > 0`, наименьший `index`. Смещение внутри блока: символ на строке, которая пересекает верх списка. Точку надо брать **внутри текста абзаца**, а не в углу элемента: у элемента есть отступ, и точка в нём даёт строку выше.

```dart
final viewportTop = listBox.localToGlobal(Offset.zero).dy;
final textTop = editable.localToGlobal(Offset.zero);
final offset = textTop.dy >= viewportTop
    ? 0
    : editable.getPositionForPoint(Offset(textTop.dx + 1, viewportTop + 1)).offset;
```

**Возврат к (блок, смещение)** в два шага, потому что высота блока неизвестна, пока он не построен:

```dart
scroll.jumpTo(index: block);                  // блок наверху, он построен
await WidgetsBinding.instance.endOfFrame;
final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
final shift = editable.localToGlobal(caret.topLeft).dy - viewportTop;
scroll.jumpTo(index: block, alignment: -shift / viewportHeight);
```

Сдвиг меряется на экране, поэтому отступ элемента учтён. Отрицательный `alignment` пакет принимает.

Точность: **до строки**. После возврата первая видимая строка — та, где лежит смещение. Тест проверяет это для пяти позиций: начало блока, середина, конец, другой блок, второй символ. Сам символ внутри строки не восстанавливается: позиция чтения — это строка наверху. Для T-017 этого достаточно.

Старый вариант без учёта отступа ошибался на строку (вместо символа 200 возвращал 150). Тест эту ошибку ловит.

## 3. Прокрутка

**Замер не выполнен.** В песочнице агента Xcode не может писать в `~/Library`, и macOS-приложение не собирается. Харнесс готов:

- `integration_test/scroll_perf_test.dart`: 40 бросков вниз, 20 вверх внутри `traceAction`.
- `test_driver/perf_driver.dart`: печатает p99 build и raster, среднее build, число кадров и пропуски бюджета.

```
flutter drive --driver=test_driver/perf_driver.dart --target=integration_test/scroll_perf_test.dart --profile -d macos
```

| Метрика | Значение |
|---|---|
| p99 build, мс | ждёт запуска на Mac |
| p99 raster, мс | ждёт запуска на Mac |
| среднее build, мс | ждёт запуска на Mac |
| кадров / пропусков бюджета | ждёт запуска на Mac |

Порог: p99 build и raster не больше 16 мс.

## 4. Своя кнопка в контекстном меню

Можно: `contextMenuBuilder` и `AdaptiveTextSelectionToolbar.buttonItems`. К штатным `contextMenuButtonItems` добавляется свой `ContextMenuButtonItem`.

```dart
contextMenuBuilder: (context, s) => AdaptiveTextSelectionToolbar.buttonItems(
  anchors: s.contextMenuAnchors,
  buttonItems: [
    ...s.contextMenuButtonItems,
    ContextMenuButtonItem(
      label: 'Translate',
      onPressed: () {
        final sel = s.textEditingValue.selection;
        onTranslate(sel.textInside(s.textEditingValue.text));
        s.hideToolbar();
      },
    ),
  ],
),
```

Тест: правый клик по выделенному слову показывает «Translate», кнопка отдаёт выделенный текст.

**Ограничение:** каждый абзац — отдельный `SelectableText`, поэтому выделение не переходит через границу абзаца. Фраза на стыке двух абзацев не выделится. Если это нужно, в T-016 смотреть `SelectionArea` над списком.

## Что подтвердить на Mac

Из `spikes/reader`:

1. Замер из пункта 3, числа вписать в таблицу.
2. `flutter run -d macos`, затем руками:
   - клик по слову: через ~0,3 с слово в заголовке окна;
   - двойной клик: выделено одно слово, в заголовке ничего нового;
   - протяжка мышью выделяет фразу;
   - правый клик по выделению: есть «Translate»;
   - кнопка `pos` печатает первый видимый блок в консоль.

Код спайка в `app/` не переносится: T-016 пишет рендерер заново по этим выводам.
