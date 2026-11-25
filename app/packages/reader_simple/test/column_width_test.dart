import 'package:core/domain_books.dart';
import 'package:core_testing/core_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:reader_simple/src/block_view.dart';
import 'package:reader_simple/src/reader_style.dart';

import 'fake_text_analyzer.dart';

const _bookId = BookId('b');
const _fontSize = 20.0;

/// Max width of the text column (T-111).
void main() {
  Future<SimpleReaderEngine> open(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = SimpleReaderEngine(analyzer: FakeTextAnalyzer())
      ..applySettings(const ReaderSettings(fontSize: _fontSize));
    addTearDown(engine.dispose);
    await engine.load(
      FakeOpenedBook(
        chapters: [
          [for (var j = 0; j < 40; j++) 'p$j lorem ipsum dolor'].join('\n\n'),
        ],
      ),
      bookId: _bookId,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: engine.buildView)),
      ),
    );
    await tester.pump();
    return engine;
  }

  final first = find.byType(BlockView).first;

  testWidgets('on a wide view the column is limited and centred', (
    tester,
  ) async {
    await open(tester, 1600);

    final rect = tester.getRect(first);
    expect(rect.width, _fontSize * ReaderStyle.maxColumnEms);
    expect(rect.center.dx, 800);
  });

  testWidgets('on a narrow view the block takes the whole width', (
    tester,
  ) async {
    await open(tester, 400);

    final rect = tester.getRect(first);
    expect(rect.left, 0);
    expect(rect.width, 400);
  });

  testWidgets('dragging outside the column scrolls the text', (tester) async {
    await open(tester, 1600);
    final rect = tester.getRect(first);
    expect(rect.left, greaterThan(100), reason: 'the margin is empty');

    await tester.dragFrom(const Offset(50, 400), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(BlockView).first).top,
      lessThan(rect.top),
    );
  });
}
