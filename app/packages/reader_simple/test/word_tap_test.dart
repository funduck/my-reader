import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:reader_simple/src/interactions.dart';
import 'package:reader_simple/src/reader_view.dart' show ReaderView;

import 'fake_text_analyzer.dart';

const _bookId = BookId('book-1');

class _DocBook implements OpenedBook {
  new(this._doc) : spine = const [ChapterRef(href: 'c0.xhtml', index: 0)];

  final ContentDocument _doc;

  @override
  final List<ChapterRef> spine;

  @override
  List<TocEntry> get toc => const [];

  @override
  Future<ContentDocument> chapter(ChapterRef ref) async => _doc;

  @override
  Future<Uint8List> resource(String href) async => throw ArgumentError(href);

  @override
  Future<void> close() async {}
}

class _Harness {
  new(this.engine, this.analyzer, this.events);

  final SimpleReaderEngine engine;
  final FakeTextAnalyzer analyzer;
  final List<ReaderEvent> events;

  /// The selection events, without position reports.
  List<TextSelected> get taps => events.whereType<TextSelected>().toList();
}

Future<_Harness> _open(
  WidgetTester tester,
  OpenedBook book, {
  bool translate = false,
}) async {
  final analyzer = FakeTextAnalyzer();
  final engine = SimpleReaderEngine(analyzer: analyzer)
    ..applySettings(ReaderSettings(translateOnSelect: translate));
  addTearDown(engine.dispose);
  final events = <ReaderEvent>[];
  final sub = engine.events.listen(events.add);
  addTearDown(sub.cancel);
  await engine.load(book, bookId: _bookId);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Builder(builder: engine.buildView)),
    ),
  );
  await tester.pump();
  return _Harness(engine, analyzer, events);
}

Future<_Harness> _openText(
  WidgetTester tester,
  String chapter, {
  bool translate = false,
}) => _open(tester, FakeOpenedBook(chapters: [chapter]), translate: translate);

RenderEditable? _findEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) => found ??= _findEditable(child));
  return found;
}

Finder _paragraph(String contains) => find.byWidgetPredicate(
  (w) =>
      w is SelectableText &&
      (w.textSpan?.toPlainText().contains(contains) ?? false),
);

/// The centre of the first occurrence of [word] in the paragraph that
/// contains [inParagraph], in global coordinates.
Offset _centerOf(WidgetTester tester, String inParagraph, String word) {
  final finder = _paragraph(inParagraph);
  final text = tester.widget<SelectableText>(finder).textSpan!.toPlainText();
  final start = text.indexOf(word);
  expect(start, greaterThanOrEqualTo(0), reason: '"$word" in "$text"');
  final editable = _findEditable(tester.renderObject(finder))!;
  final box = editable
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      )
      .first;
  return editable.localToGlobal(box.toRect().center);
}

/// A finger that rests on [at] for the long press (500 ms) and goes up.
Future<void> _hold(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
  await gesture.up();
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
}

/// The spans of the paragraph that contains [inParagraph] drawn with a
/// background.
List<TextSpan> _marked(WidgetTester tester, String inParagraph) {
  final span = tester.widget<SelectableText>(_paragraph(inParagraph)).textSpan!;
  final result = <TextSpan>[];
  span.visitChildren((s) {
    if (s is TextSpan && s.style?.backgroundColor != null) result.add(s);
    return true;
  });
  return result;
}

/// A click of the primary mouse button; a mouse has no selection handles that
/// could catch a second click.
Future<void> _click(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await gesture.up();
}

/// Selects `[start, end)` of the paragraph and opens the selection menu.
Future<void> _select(
  WidgetTester tester,
  String inParagraph,
  int start,
  int end,
) async {
  final editable = tester.state<EditableTextState>(
    find.descendant(
      of: _paragraph(inParagraph),
      matching: find.byType(EditableText),
    ),
  );
  editable.userUpdateTextEditingValue(
    editable.textEditingValue.copyWith(
      selection: TextSelection(baseOffset: start, extentOffset: end),
    ),
    SelectionChangedCause.toolbar,
  );
  editable.showToolbar();
  await tester.pump();
}

/// The single-tap events (T-087).
List<ViewTapped> _viewTaps(_Harness h) =>
    h.events.whereType<ViewTapped>().toList();

/// A quick touch tap on [at]; waits out the double-tap window.
Future<void> _touchTap(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
}

/// A quick click of the primary mouse button on [at]; waits out the
/// double-click window.
Future<void> _quickClick(WidgetTester tester, Offset at) async {
  await _click(tester, at);
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
}

void _viewTapTests({required bool mouse}) {
  Future<void> tap(WidgetTester tester, Offset at) =>
      mouse ? _quickClick(tester, at) : _touchTap(tester, at);

  Size viewSize(WidgetTester tester) => tester.getSize(find.byType(ReaderView));

  testWidgets('a tap on a word gives one ViewTapped with point and size', (
    tester,
  ) async {
    final h = await _openText(tester, _fox);
    final at = _centerOf(tester, 'quick', 'brown');
    await tap(tester, at);

    expect(h.taps, isEmpty);
    expect(_viewTaps(h), [ViewTapped(position: at, size: viewSize(tester))]);
  });

  testWidgets('a tap on empty space under the chapter gives ViewTapped', (
    tester,
  ) async {
    final h = await _openText(tester, _fox);
    const at = Offset(300, 450);
    expect(find.byType(SelectableText).hitTestable(), findsOneWidget);
    await tap(tester, at);

    expect(_viewTaps(h), [ViewTapped(position: at, size: viewSize(tester))]);
  });

  testWidgets('a tap on the margin gives ViewTapped', (tester) async {
    final h = await _openText(tester, _fox);
    final text = tester.getRect(find.byType(SelectableText));
    final at = Offset(4, text.center.dy);
    await tap(tester, at);

    expect(_viewTaps(h), [ViewTapped(position: at, size: viewSize(tester))]);
  });

  testWidgets('the event comes after the double-tap window', (tester) async {
    final h = await _openText(tester, _fox);
    final gesture = await tester.startGesture(
      _centerOf(tester, 'quick', 'brown'),
      kind: mouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
    );
    await gesture.up();
    await tester.pump(kDoubleTapTimeout - const Duration(milliseconds: 10));
    expect(_viewTaps(h), isEmpty);
    await tester.pump(const Duration(milliseconds: 20));
    expect(_viewTaps(h), hasLength(1));
  });

  testWidgets('a hold of 500 ms gives no ViewTapped', (tester) async {
    final h = await _openText(tester, _fox);
    final at = _centerOf(tester, 'quick', 'brown');
    final gesture = await tester.startGesture(
      at,
      kind: mouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    await gesture.up();
    await tester.pump(kDoubleTapTimeout * 2);

    expect(_viewTaps(h), isEmpty);
  });

  testWidgets('a double tap gives no ViewTapped', (tester) async {
    final h = await _openText(tester, _fox);
    final at = _centerOf(tester, 'quick', 'brown');
    if (mouse) {
      await _click(tester, at);
      await tester.pump(kDoubleTapMinTime);
      await _click(tester, at);
    } else {
      await tester.tapAt(at);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(at);
    }
    await tester.pump(kDoubleTapTimeout * 2);

    expect(_viewTaps(h), isEmpty);
    expect(h.taps, isEmpty);
  });

  testWidgets('a drag gives no ViewTapped', (tester) async {
    final h = await _openText(tester, _fox);
    final gesture = await tester.startGesture(
      _centerOf(tester, 'quick', 'quick'),
      kind: mouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pump(kDoubleTapTimeout * 2);

    expect(_viewTaps(h), isEmpty);
  });

  testWidgets('a scroll gives no ViewTapped', (tester) async {
    final h = await _open(tester, FakeOpenedBook(chapters: [_longChapter()]));
    final gesture = await tester.startGesture(const Offset(300, 450));
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump(kDoubleTapTimeout * 2);

    expect(_viewTaps(h), isEmpty);
  });

  testWidgets('a tap that only clears a selection gives no ViewTapped', (
    tester,
  ) async {
    final h = await _openText(tester, _fox);
    await _select(tester, 'quick', 4, 9);
    await tap(tester, const Offset(300, 450));
    expect(_viewTaps(h), isEmpty);

    // The selection is gone: the next tap counts.
    await tap(tester, const Offset(300, 450));
    expect(_viewTaps(h), hasLength(1));
  });

  testWidgets('a tap on Next chapter opens it and gives no ViewTapped', (
    tester,
  ) async {
    final h = await _open(
      tester,
      FakeOpenedBook(chapters: ['First chapter text.', 'Second chapter text.']),
    );
    await tap(tester, tester.getCenter(find.text('Next chapter')));
    await tester.pump();

    expect(find.textContaining('Second chapter text.'), findsOneWidget);
    expect(_viewTaps(h), isEmpty);

    // The next tap is not swallowed.
    await tap(tester, const Offset(300, 450));
    expect(_viewTaps(h), hasLength(1));
  });
}

String _longChapter() =>
    List.filled(60, 'A paragraph of the long chapter.').join('\n\n');

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

const _fox = 'The quick brown fox jumps. It was over the lazy dog.';

/// The paragraph's editable.
EditableTextState _editableOf(WidgetTester tester) =>
    tester.state<EditableTextState>(find.byType(EditableText).first);

String _selectedText(WidgetTester tester) {
  final editable = _editableOf(tester);
  final selection = editable.textEditingValue.selection;
  if (!selection.isValid) return '';
  return selection.textInside(editable.textEditingValue.text);
}

/// Records what goes to the clipboard.
List<String> _mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        copied.add(args['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

const _held = Duration(milliseconds: 510);

/// The centre of the right-hand selection handle (the end of the selection).
Offset _endHandle(WidgetTester tester) {
  final handles = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_SelectionHandleOverlay',
  );
  expect(handles, findsNWidgets(2));
  return [
    for (var i = 0; i < 2; i++)
      tester.getCenter(
        find
            .descendant(
              of: handles.at(i),
              matching: find.byType(GestureDetector),
            )
            .first,
      ),
  ].reduce((a, b) => a.dx > b.dx ? a : b);
}

void main() {
  group('tap', () {
    testWidgets('a tap on a word gives ViewTapped, no mark, no selection', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      await tester.tapAt(_centerOf(tester, 'quick', 'brown'));
      await tester.pump(kDoubleTapTimeout * 2);

      expect(_viewTaps(h), hasLength(1));
      expect(h.taps, isEmpty);
      expect(_marked(tester, 'quick'), isEmpty);
      expect(_selectedText(tester), isEmpty);
      expect(find.text('Translate'), findsNothing);
    });

    testWidgets('a touch down alone draws and selects nothing', (tester) async {
      final h = await _openText(tester, _fox);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_marked(tester, 'quick'), isEmpty);
      expect(_selectedText(tester), isEmpty);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);
      expect(h.taps, isEmpty);
    });

    testWidgets('a touch released before 500 ms selects nothing', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, isEmpty);
      expect(_selectedText(tester), isEmpty);
    });
  });

  group('double tap with a finger', () {
    for (final translate in [true, false]) {
      testWidgets('selects nothing and gives no event (translate $translate)', (
        tester,
      ) async {
        final h = await _openText(tester, _fox, translate: translate);
        final at = _centerOf(tester, 'quick', 'brown');
        await tester.tapAt(at);
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(at);
        await tester.pump(kDoubleTapTimeout * 2);

        expect(_selectedText(tester), isEmpty);
        expect(h.taps, isEmpty);
        expect(_viewTaps(h), isEmpty);
        expect(find.text('Translate'), findsNothing);
      });
    }

    testWidgets('a hold on another word after a tap selects it', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      await tester.tapAt(_centerOf(tester, 'quick', 'brown'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await _hold(tester, _centerOf(tester, 'quick', 'lazy'));
      expect(h.taps.single.text, 'lazy');
    });

    testWidgets('two single taps far apart in time both count', (tester) async {
      final h = await _openText(tester, _fox);
      final at = _centerOf(tester, 'quick', 'brown');
      await tester.tapAt(at);
      await tester.pump(kDoubleTapTimeout * 2);
      await tester.tapAt(at);
      await tester.pump(kDoubleTapTimeout * 2);
      expect(_viewTaps(h), hasLength(2));
    });
  });

  group('hold, translateOnSelect on', () {
    testWidgets('gives one TextSelected after release, selection collapsed', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(_held);
      // Selected, but the finger is still down: not ready.
      expect(_selectedText(tester), 'brown');
      expect(h.taps, isEmpty);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, hasLength(1));
      final event = h.taps.single;
      expect(event.text, 'brown');
      expect(event.sentence, 'The quick brown fox jumps.');
      expect(event.at.book, _bookId);
      expect(
        event.at.chapter,
        const ChapterRef(href: 'chapter1.xhtml', index: 0),
      );
      expect(event.at.engineHint, 'simple:1:0:0:10');
      expect(event.at.quote!.exact, 'brown');
      expect(event.at.quote!.prefix, 'The quick ');
      expect(event.at.progression, closeTo(10 / _fox.length, 1e-9));
      expect(_selectedText(tester), isEmpty);
      expect(find.text('Translate'), findsNothing);
      expect(find.text('Copy'), findsNothing);
      expect(_viewTaps(h), isEmpty);
    });

    testWidgets('works through the dim layer', (tester) async {
      final h = await _openText(tester, _fox, translate: true);
      h.engine.applySettings(
        const ReaderSettings(translateOnSelect: true, dim: 0.5),
      );
      await tester.pump();
      await _hold(tester, _centerOf(tester, 'quick', 'brown'));
      expect(h.taps.single.text, 'brown');
    });

    testWidgets('a word in the second sentence gets that sentence', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      await _hold(tester, _centerOf(tester, 'quick', 'lazy'));

      expect(h.taps.single.text, 'lazy');
      expect(h.taps.single.sentence, 'It was over the lazy dog.');
    });

    testWidgets('punctuation is not part of the word', (tester) async {
      final h = await _openText(
        tester,
        'Well, "stop" now (please)!',
        translate: true,
      );
      await _hold(tester, _centerOf(tester, 'Well', 'stop'));
      await _hold(tester, _centerOf(tester, 'Well', 'please'));

      expect([for (final e in h.taps) e.text], ['stop', 'please']);
    });

    testWidgets('a touch that moves 20 px at 100 ms selects nothing', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(_held);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, isEmpty);
      expect(_selectedText(tester), isEmpty);
    });

    testWidgets('the Locator of a hold in a list item points into the item', (
      tester,
    ) async {
      final h = await _open(
        tester,
        _DocBook(
          const ContentDocument([
            ListBlock(
              ordered: false,
              items: [
                [TextInline('first one')],
                [TextInline('second item here')],
              ],
            ),
          ]),
        ),
        translate: true,
      );
      await _hold(tester, _centerOf(tester, 'second', 'item'));

      final event = h.taps.single;
      expect(event.text, 'item');
      expect(event.sentence, 'second item here');
      // "first one" (9) + the newline + "second " (7).
      expect(event.at.engineHint, 'simple:1:0:0:17');
      expect(event.at.quote!.exact, 'item');
    });

    testWidgets('a hold in a quoted paragraph points into the block', (
      tester,
    ) async {
      final h = await _open(
        tester,
        _DocBook(
          const ContentDocument([
            ParagraphBlock([TextInline('Before.')]),
            QuoteBlock([
              ParagraphBlock([TextInline('one')]),
              ParagraphBlock([TextInline('two three')]),
            ]),
          ]),
        ),
        translate: true,
      );
      await _hold(tester, _centerOf(tester, 'two', 'three'));

      final event = h.taps.single;
      expect(event.text, 'three');
      // Block 1; "one" (3) + the newline + "two " (4).
      expect(event.at.engineHint, 'simple:1:0:1:8');
    });

    testWidgets('no event after dispose', (tester) async {
      final h = await _openText(tester, _fox, translate: true);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(_held);
      await tester.pumpWidget(const SizedBox());
      await gesture.up();
      await tester.pump(_held * 2);
      expect(h.taps, isEmpty);
    });
  });

  group('hold, translateOnSelect off', () {
    testWidgets('shows a toolbar with Translate and Copy only', (tester) async {
      final h = await _openText(tester, _fox);
      await _hold(tester, _centerOf(tester, 'quick', 'brown'));

      expect(h.taps, isEmpty);
      expect(_selectedText(tester), 'brown');
      expect(find.text('Translate'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Select all'), findsNothing);
      expect(find.text('Cut'), findsNothing);
      expect(find.text('Paste'), findsNothing);
    });

    testWidgets('Translate gives TextSelected and collapses the selection', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      await _hold(tester, _centerOf(tester, 'quick', 'brown'));
      await tester.tap(find.text('Translate'));
      await tester.pump();

      expect(h.taps.single.text, 'brown');
      expect(_selectedText(tester), isEmpty);
      expect(find.text('Translate'), findsNothing);
    });

    testWidgets('Copy puts the text on the clipboard and gives no event', (
      tester,
    ) async {
      final copied = _mockClipboard(tester);
      final h = await _openText(tester, _fox);
      await _hold(tester, _centerOf(tester, 'quick', 'brown'));
      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(copied, ['brown']);
      expect(h.taps, isEmpty);
    });

    testWidgets('a tap elsewhere hides the toolbar', (tester) async {
      final h = await _openText(tester, _fox);
      await _hold(tester, _centerOf(tester, 'quick', 'brown'));
      await tester.tapAt(const Offset(300, 450));
      await tester.pump(kDoubleTapTimeout * 2);

      expect(find.text('Translate'), findsNothing);
      expect(h.engine.hasSelection, isFalse);
      expect(_viewTaps(h), isEmpty);
    });
  });

  group('extending the selection', () {
    testWidgets('a hold then a drag gives one event after release', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
      );
      await tester.pump(_held);
      await gesture.moveTo(_centerOf(tester, 'quick', 'jumps'));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.taps, isEmpty);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, hasLength(1));
      expect(h.taps.single.text, contains('brown'));
      expect(h.taps.single.text, contains('jump'));
    });

    testWidgets('dragging a handle gives no event until Translate', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      await _hold(tester, _centerOf(tester, 'quick', 'brown'));
      expect(_selectedText(tester), 'brown');

      final end = _endHandle(tester);
      final target = _centerOf(tester, 'quick', 'fox');
      final gesture = await tester.startGesture(end);
      final dx = (target.dx - end.dx) / 8;
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(Offset(dx, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, isEmpty);
      expect(_selectedText(tester), startsWith('brown'));
      expect(_selectedText(tester).length, greaterThan('brown'.length));
      await tester.tap(find.text('Translate'));
      await tester.pump();
      expect(h.taps, hasLength(1));
      expect(h.taps.single.text, contains('brown'));
      expect(h.taps.single.text, contains('fo'));
    });

    testWidgets('dragging a handle gives one event after release when '
        'translate is on', (tester) async {
      final h = await _openText(tester, _fox);
      await _hold(tester, _centerOf(tester, 'quick', 'brown'));
      h.engine.applySettings(const ReaderSettings(translateOnSelect: true));
      await tester.pump();

      final end = _endHandle(tester);
      final target = _centerOf(tester, 'quick', 'fox');
      final gesture = await tester.startGesture(end);
      final dx = (target.dx - end.dx) / 8;
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(Offset(dx, 0));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.taps, isEmpty);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, hasLength(1));
      expect(h.taps.single.text, contains('fo'));
      expect(_selectedText(tester), isEmpty);
    });
  });

  group('mouse', () {
    testWidgets('a double click selects the word and gives one event', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      final at = _centerOf(tester, 'quick', 'brown');
      await _click(tester, at);
      await tester.pump(kDoubleTapMinTime);
      await _click(tester, at);
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps.map((e) => e.text), ['brown']);
      expect(_selectedText(tester), isEmpty);
      expect(_viewTaps(h), isEmpty);
    }, variant: _macOS);

    testWidgets('a double click shows the toolbar when translate is off', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      final at = _centerOf(tester, 'quick', 'brown');
      await _click(tester, at);
      await tester.pump(kDoubleTapMinTime);
      await _click(tester, at);
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, isEmpty);
      expect(_selectedText(tester), 'brown');
      expect(find.text('Translate'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(find.text('Translate'));
      await tester.pump();
      expect(h.taps.map((e) => e.text), ['brown']);
    }, variant: _macOS);

    testWidgets('a drag gives one event after the button is released', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'quick'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(_centerOf(tester, 'quick', 'brown'));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(_centerOf(tester, 'quick', 'fox'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.taps, isEmpty);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, hasLength(1));
      expect(h.taps.single.text, contains('brown'));
      expect(_selectedText(tester), isEmpty);
    }, variant: _macOS);

    testWidgets('a drag shows the toolbar when translate is off', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'quick'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(_centerOf(tester, 'quick', 'fox'));
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, isEmpty);
      expect(_selectedText(tester), isNotEmpty);
      expect(find.text('Translate'), findsOneWidget);
    }, variant: _macOS);

    testWidgets('a held mouse button without moving selects nothing', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'brown'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(_held);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);

      expect(h.taps, isEmpty);
      expect(_selectedText(tester), isEmpty);
    }, variant: _macOS);

    testWidgets('a click clears a selection and gives no event', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      final gesture = await tester.startGesture(
        _centerOf(tester, 'quick', 'quick'),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(_centerOf(tester, 'quick', 'fox'));
      await gesture.up();
      await tester.pump(kDoubleTapTimeout * 2);
      expect(_selectedText(tester), isNotEmpty);

      await _quickClick(tester, const Offset(300, 450));
      expect(h.taps, isEmpty);
      expect(_viewTaps(h), isEmpty);
    }, variant: _macOS);
  });

  group('single tap on the view, touch', () => _viewTapTests(mouse: false));

  group('single tap on the view, mouse', () {
    _viewTapTests(mouse: true);
  });

  group('sentence at a paragraph boundary', () {
    // The first paragraph does not end with a sentence mark; the second
    // continues the thought. A splitter run over both would glue them.
    const first = 'The old man walked slowly down the road';
    const second = 'and then he stopped. A dog barked.';

    testWidgets('the end of a paragraph is not joined with the next one', (
      tester,
    ) async {
      final h = await _openText(tester, '$first\n\n$second', translate: true);
      await _hold(tester, _centerOf(tester, 'old man', 'road'));

      final event = h.taps.single;
      expect(event.text, 'road');
      expect(event.sentence, first);
      expect(event.sentence, isNot(contains('and then')));
      expect(h.analyzer.sentenceCalls, [first]);
    });

    testWidgets('the start of a paragraph is not joined with the previous', (
      tester,
    ) async {
      final h = await _openText(tester, '$first\n\n$second', translate: true);
      await _hold(tester, _centerOf(tester, 'and then', 'and'));

      final event = h.taps.single;
      expect(event.text, 'and');
      expect(event.sentence, 'and then he stopped.');
      expect(h.analyzer.sentenceCalls, [second]);
    });
  });

  group('selection', () {
    testWidgets('the Translate button emits TextSelected', (tester) async {
      final h = await _openText(tester, _fox);
      await _select(tester, 'quick', 4, 15);

      expect(find.text('Translate'), findsOneWidget);
      await tester.tap(find.text('Translate'));
      await tester.pump();

      expect(h.taps, hasLength(1));
      final event = h.taps.single;
      expect(event.text, 'quick brown');
      expect(event.sentence, 'The quick brown fox jumps.');
      expect(event.at.engineHint, 'simple:1:0:0:4');
      expect(event.at.quote!.exact, 'quick brown');
      expect(event.at.chapter.index, 0);
      expect(find.text('Translate'), findsNothing);
    });

    testWidgets('a selection over two sentences gives both', (tester) async {
      final h = await _openText(tester, _fox);
      await _select(tester, 'quick', 16, 29);
      await tester.tap(find.text('Translate'));
      await tester.pump();

      final event = h.taps.single;
      expect(event.text, 'fox jumps. It');
      expect(event.sentence, _fox);
    });

    testWidgets('spaces around the selection are cut off', (tester) async {
      final h = await _openText(tester, _fox);
      await _select(tester, 'quick', 3, 16);
      await tester.tap(find.text('Translate'));
      await tester.pump();

      final event = h.taps.single;
      expect(event.text, 'quick brown');
      expect(event.at.engineHint, 'simple:1:0:0:4');
    });

    testWidgets('there is no Translate button without a selection', (
      tester,
    ) async {
      await _openText(tester, _fox);
      await tester.tap(_paragraph('quick'), buttons: kSecondaryButton);
      await tester.pump();
      expect(find.text('Translate'), findsNothing);
    });
  });

  group('highlight', () {
    testWidgets('a Locator from an event is drawn with a background', (
      tester,
    ) async {
      final h = await _openText(tester, _fox, translate: true);
      await _hold(tester, _centerOf(tester, 'quick', 'brown'));
      final at = h.taps.single.at;

      h.engine.highlight([at]);
      await tester.pump();

      expect([for (final s in _marked(tester, 'quick')) s.text], ['brown']);
      expect(
        tester
            .widget<SelectableText>(_paragraph('quick'))
            .textSpan!
            .toPlainText(),
        _fox,
      );
    });

    testWidgets('a phrase over inline styles and a new call replaces', (
      tester,
    ) async {
      final h = await _open(
        tester,
        _DocBook(
          const ContentDocument([
            ParagraphBlock([
              TextInline('plain '),
              BoldInline([TextInline('heavy words')]),
              TextInline(' after'),
            ]),
          ]),
        ),
      );
      const text = 'plain heavy words after';
      Locator at(String exact, int offset) => Locator(
        book: _bookId,
        chapter: h.engine.chapter.value!.ref!,
        progression: 0,
        quote: TextQuote.fromText(text, offset, offset + exact.length),
        engineHint: 'simple:1:0:0:$offset',
      );

      h.engine.highlight([at('in heavy wor', 3)]);
      await tester.pump();
      expect(
        [for (final s in _marked(tester, 'plain')) s.text],
        ['in ', 'heavy wor'],
      );

      h.engine.highlight([at('words after', 12)]);
      await tester.pump();
      expect(
        [for (final s in _marked(tester, 'plain')) s.text],
        ['words', ' after'],
      );

      h.engine.highlight(const []);
      await tester.pump();
      expect(_marked(tester, 'plain'), isEmpty);
    });

    testWidgets('a Locator of another chapter or a lost quote is skipped', (
      tester,
    ) async {
      final h = await _openText(tester, _fox);
      final chapter = h.engine.chapter.value!.ref!;
      h.engine.highlight([
        const Locator(
          book: _bookId,
          chapter: ChapterRef(href: 'other.xhtml', index: 4),
          progression: 0,
          quote: TextQuote(exact: 'quick'),
        ),
        Locator(
          book: _bookId,
          chapter: chapter,
          progression: 0.5,
          quote: const TextQuote(exact: 'missing'),
        ),
        Locator(book: _bookId, chapter: chapter, progression: 0.5),
      ]);
      await tester.pump();
      expect(_marked(tester, 'quick'), isEmpty);
    });
  });

  group('sentence helper', () {
    test('sentenceAround falls back to the whole text', () {
      final analyzer = _NoSentences();
      expect(sentenceAround(analyzer, ' some text ', 1, 5), 'some text');
    });
  });
}

class _NoSentences implements TextAnalyzer {
  @override
  List<SentenceSpan> sentences(String text) => const [];

  @override
  List<TextToken> tokens(String text) => const [];

  @override
  String lemma(String word) => word;
}
