import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_spike/reader.dart';
import 'package:reader_spike/text_gen.dart';
import 'package:reader_spike/word_at.dart';

Widget app(List<String> p, SpikeEvents e, ReaderSpikeController c) =>
    MaterialApp(
      home: Scaffold(
        body: ReaderSpike(paragraphs: p, events: e, controller: c),
      ),
    );

/// The [RenderEditable] of the paragraph [block], which must be built.
RenderEditable editableOf(WidgetTester t, List<String> p, int block) {
  final finder = find.byWidgetPredicate(
    (w) => w is SelectableText && w.textSpan?.toPlainText() == p[block],
  );
  return findRenderEditable(t.element(finder))!;
}

/// Global center of the glyph box of char [k] in paragraph [block].
Offset charCenter(WidgetTester t, List<String> p, int block, int k) {
  final editable = editableOf(t, p, block);
  final box = editable
      .getBoxesForSelection(TextSelection(baseOffset: k, extentOffset: k + 1))
      .first;
  return editable.localToGlobal(box.toRect().center);
}

/// Top of the line that holds char [offset], in the paragraph's coordinates.
double lineTop(RenderEditable editable, int offset) =>
    editable.getLocalRectForCaret(TextPosition(offset: offset)).top;

Future<void> goTo(WidgetTester t, ReaderSpikeController c, SpikeLocator l) {
  // goTo waits for a frame, so pump before awaiting it.
  final done = c.goTo(l);
  return t.pump().then((_) => t.pump()).then((_) => done);
}

Future<void> mouseDoubleClick(WidgetTester t, Offset pos) async {
  final g = await t.startGesture(pos, kind: PointerDeviceKind.mouse);
  await g.up();
  await t.pump(const Duration(milliseconds: 50));
  await g.down(pos);
  await g.up();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  test('chapter has about 15000 words', () {
    final words = generateChapter().fold<int>(
      0,
      (a, p) => a + p.split(RegExp(r'\s+')).length,
    );
    expect(words, inInclusiveRange(15000, 15200));
  });

  testWidgets('tap yields the word under it, after the tap delay', (t) async {
    final p = generateChapter();
    final e = SpikeEvents();
    await t.pumpWidget(app(p, e, ReaderSpikeController()));
    const k = 10;
    await t.tapAt(charCenter(t, p, 0, k));
    await t.pump(const Duration(milliseconds: 100));
    expect(e.lastWord.value, isNull, reason: 'reported before the delay');
    await t.pump(const Duration(milliseconds: 300));
    final w = wordRangeAt(p[0], k)!;
    expect(e.lastWord.value, '${w.textInside(p[0])}@0:${w.start}');
  });

  testWidgets('tap after scrolling yields the word in that block', (t) async {
    final p = generateChapter();
    final e = SpikeEvents();
    final c = ReaderSpikeController();
    await t.pumpWidget(app(p, e, c));
    await goTo(t, c, const SpikeLocator(50, 0));
    const k = 30;
    await t.tapAt(charCenter(t, p, 50, k));
    await t.pump(const Duration(milliseconds: 400));
    final w = wordRangeAt(p[50], k)!;
    expect(e.lastWord.value, '${w.textInside(p[50])}@50:${w.start}');
  });

  testWidgets('goTo restores the exact line, first visible reads it back', (
    t,
  ) async {
    final p = generateChapter();
    final c = ReaderSpikeController();
    await t.pumpWidget(app(p, SpikeEvents(), c));
    expect(c.firstVisible(), isA<SpikeLocator>());
    expect(c.firstVisible()!.block, 0);
    expect(c.firstVisible()!.offset, 0);

    final targets = [
      const SpikeLocator(80, 0),
      const SpikeLocator(80, 200),
      SpikeLocator(80, p[80].length - 5),
      const SpikeLocator(120, 350),
      const SpikeLocator(3, 1),
    ];
    for (final want in targets) {
      await goTo(t, c, want);
      final got = c.firstVisible()!;
      expect(got.block, want.block, reason: 'block for $want');
      final editable = editableOf(t, p, want.block);
      expect(
        lineTop(editable, got.offset),
        lineTop(editable, want.offset),
        reason: 'line for $want, got $got',
      );
    }
  });

  testWidgets('double click selects one word and reports no tap', (t) async {
    final p = generateChapter();
    final e = SpikeEvents();
    await t.pumpWidget(app(p, e, ReaderSpikeController()));
    await mouseDoubleClick(t, charCenter(t, p, 0, 10));
    expect(e.lastSelection.value, isNotNull);
    expect(e.lastSelection.value!.contains(' '), isFalse);
    expect(e.lastWord.value, isNull, reason: 'double click fired a tap');
  });

  testWidgets('right click on a selection offers the custom button', (t) async {
    final p = generateChapter();
    final e = SpikeEvents();
    await t.pumpWidget(app(p, e, ReaderSpikeController()));
    final pos = charCenter(t, p, 0, 10);
    await mouseDoubleClick(t, pos);
    final r = await t.startGesture(
      pos,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await r.up();
    await t.pumpAndSettle();
    expect(find.text('Translate'), findsOneWidget);
    await t.tap(find.text('Translate'));
    await t.pump();
    expect(e.lastMenuAction.value, e.lastSelection.value);
  });
}
