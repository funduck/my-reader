import 'dart:async';
import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_api/reader_api.dart';

const _chapter = ChapterRef(href: 'c1.xhtml', index: 0);

String describe(ReaderEvent event) => switch (event) {
  PositionChanged() => 'position',
  TextSelected(:final text) => 'selected $text',
  ViewTapped(:final position) => 'view tapped ${position.dx}',
  ChapterFinished(:final chapter) => 'finished ${chapter.index}',
};

class _FakeEngine implements ReaderEngine {
  final _controller = StreamController<ReaderEvent>.broadcast();

  @override
  Widget buildView(BuildContext context) => const SizedBox();

  @override
  Future<void> load(
    OpenedBook book, {
    required BookId bookId,
    Locator? at,
  }) async {}

  @override
  Future<void> goTo(Locator locator) async {}

  @override
  void applySettings(ReaderSettings settings) {}

  @override
  void highlight(ReaderHighlights highlights) {}

  @override
  Stream<ReaderEvent> get events => _controller.stream;

  @override
  Future<void> dispose() => _controller.close();
}

void main() {
  test('ReaderEvent switch is exhaustive and distinguishes variants', () {
    expect(describe(const ChapterFinished(_chapter)), 'finished 0');
    expect(describe(const ChapterFinished(_chapter)), isNot('position'));
  });

  test('ViewTapped has value equality and carries point and size', () {
    const tap = ViewTapped(position: Offset(3, 4), size: Size(100, 200));
    expect(tap, const ViewTapped(position: Offset(3, 4), size: Size(100, 200)));
    expect(tap.hashCode, tap.hashCode);
    expect(
      tap,
      isNot(const ViewTapped(position: Offset(3, 5), size: Size(100, 200))),
    );
    expect(describe(tap), 'view tapped 3.0');
  });

  test('ChapterFinished has value equality', () {
    expect(
      const ChapterFinished(_chapter),
      const ChapterFinished(ChapterRef(href: 'c1.xhtml', index: 0)),
    );
    expect(
      const ChapterFinished(_chapter),
      isNot(const ChapterFinished(ChapterRef(href: 'c2.xhtml', index: 1))),
    );
  });

  test('ReaderSettings has value equality and copyWith', () {
    const a = ReaderSettings();
    expect(a, const ReaderSettings());
    expect(a.hashCode, const ReaderSettings().hashCode);
    final b = a.copyWith(fontSize: 22, theme: ReaderTheme.dark);
    expect(b, isNot(a));
    expect(b.fontSize, 22);
    expect(b.theme, ReaderTheme.dark);
    expect(b.horizontalPadding, a.horizontalPadding);
  });

  test('ReaderSettings.translateOnSelect is off by default and copyable', () {
    expect(const ReaderSettings().translateOnSelect, isFalse);
    final on = const ReaderSettings().copyWith(translateOnSelect: true);
    expect(on.translateOnSelect, isTrue);
    expect(on, isNot(const ReaderSettings()));
    expect(on.copyWith(fontSize: 20).translateOnSelect, isTrue);
  });

  test('ReaderSettings copyWith sets and clears the texture', () {
    final image = MemoryImage(Uint8List(0));
    final a = const ReaderSettings().copyWith(
      texture: () => image,
      lineHeight: 2,
      dim: 0.3,
    );
    expect(a.texture, same(image));
    expect(a.lineHeight, 2);
    expect(a.dim, 0.3);
    expect(a.copyWith(fontSize: 20).texture, same(image));
    expect(a.copyWith(texture: () => null).texture, isNull);
    expect(a, isNot(const ReaderSettings()));
  });

  test('HighlightKind order is the priority', () {
    expect(HighlightKind.values, [
      HighlightKind.focus,
      HighlightKind.recent,
      HighlightKind.lookedUp,
      HighlightKind.cheatSheet,
      HighlightKind.difficult,
    ]);
  });

  test('ReaderHighlights has value equality over ranges and words', () {
    const locator = Locator(
      book: BookId('b'),
      chapter: _chapter,
      progression: 0.5,
    );
    ReaderHighlights make(String word, [Locator? at]) => ReaderHighlights(
      ranges: {
        HighlightKind.focus: [?at],
      },
      words: {
        HighlightKind.difficult: {word, 'b'},
      },
    );
    final a = make('a', locator);
    expect(a, make('a', locator));
    expect(a.hashCode, make('a', locator).hashCode);
    expect(a, isNot(make('c', locator)));
    expect(a, isNot(make('a')));
    expect(
      const ReaderHighlights(ranges: {HighlightKind.recent: []}),
      isNot(const ReaderHighlights(ranges: {HighlightKind.focus: []})),
    );
  });

  test('ReaderHighlights.none and kinds without entries are empty', () {
    expect(ReaderHighlights.none.isEmpty, isTrue);
    expect(ReaderHighlights.none, ReaderHighlights.none);
    expect(
      const ReaderHighlights(
        ranges: {HighlightKind.focus: []},
        words: {HighlightKind.recent: {}},
      ).isEmpty,
      isTrue,
    );
    expect(
      const ReaderHighlights(
        words: {
          HighlightKind.recent: {'run'},
        },
      ).isEmpty,
      isFalse,
    );
  });

  test('ReaderEngineFactory produces an engine whose events can be listened '
      'to and closed', () async {
    const ReaderEngineFactory factory = _FakeEngine.new;
    final engine = factory();
    final received = <ReaderEvent>[];
    final sub = engine.events.listen(received.add);
    await engine.dispose();
    await sub.cancel();
    expect(received, isEmpty);
  });
}
