import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_api/reader_api.dart';

const _chapter = ChapterRef(href: 'c1.xhtml', index: 0);

String describe(ReaderEvent event) => switch (event) {
  PositionChanged() => 'position',
  TextSelected(:final text) => 'selected $text',
  WordTapped(:final word) => 'tapped $word',
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
  void highlight(List<Locator> ranges) {}

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
