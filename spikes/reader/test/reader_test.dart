import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
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

/// Global center of the glyph box of char [k] in the first paragraph.
Offset charCenter(WidgetTester t, int k) {
  final editable = findRenderEditable(
    t.element(find.byType(SelectableText).first),
  )!;
  final box = editable
      .getBoxesForSelection(TextSelection(baseOffset: k, extentOffset: k + 1))
      .first;
  return editable.localToGlobal(box.toRect().center);
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

  testWidgets('tap on a character yields the word under it', (t) async {
    final p = generateChapter();
    final e = SpikeEvents();
    await t.pumpWidget(app(p, e, ReaderSpikeController()));
    const k = 10;
    await t.tapAt(charCenter(t, k));
    await t.pump(const Duration(milliseconds: 400));
    final w = wordRangeAt(p[0], k)!;
    expect(e.lastWord.value, '${w.textInside(p[0])}@0:${w.start}');
  });

  testWidgets('first visible block and goTo round-trip', (t) async {
    final p = generateChapter();
    final c = ReaderSpikeController();
    await t.pumpWidget(app(p, SpikeEvents(), c));
    expect(c.firstVisible()?.block, 0);
    await c.goTo(const SpikeLocator(80, 0));
    await t.pump();
    await t.pump();
    expect(c.firstVisible()?.block, 80);
    await c.goTo(const SpikeLocator(80, 200));
    await t.pump();
    await t.pump();
    final got = c.firstVisible()!;
    expect(got.block, 80);
    expect((got.offset - 200).abs(), lessThan(60)); // about one line
  });

  testWidgets('mouse double click selects exactly one word', (t) async {
    final p = generateChapter();
    final e = SpikeEvents();
    await t.pumpWidget(app(p, e, ReaderSpikeController()));
    await mouseDoubleClick(t, charCenter(t, 10));
    expect(e.lastSelection.value, isNotNull);
    expect(e.lastSelection.value!.contains(' '), isFalse);
  });

  testWidgets('right click on a selection offers the custom button', (t) async {
    final p = generateChapter();
    final e = SpikeEvents();
    await t.pumpWidget(app(p, e, ReaderSpikeController()));
    final pos = charCenter(t, 10);
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
    expect(e.lastMenuAction.value, isNotNull);
  });
}
