import 'dart:convert';
import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_api/reader_api.dart';
import 'package:reader_simple/reader_simple.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

const _bookId = BookId('book-1');

/// 1x1 transparent PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// A book whose chapters are given as documents.
class _DocBook implements OpenedBook {
  new(this._docs, {this.resources = const {}})
    : spine = [
        for (var i = 0; i < _docs.length; i++)
          ChapterRef(href: 'c$i.xhtml', index: i),
      ];

  final List<ContentDocument> _docs;
  final Map<String, Uint8List> resources;

  @override
  final List<ChapterRef> spine;

  @override
  List<TocEntry> get toc => const [];

  @override
  Future<ContentDocument> chapter(ChapterRef ref) async => _docs[ref.index];

  @override
  Future<Uint8List> resource(String href) async {
    final bytes = resources[href];
    if (bytes == null) throw ArgumentError.value(href);
    return bytes;
  }

  @override
  Future<void> close() async {}
}

/// Chapter [c] text: [count] paragraphs, `c<c>-p<j>` each.
String _chapterText(int c, int count) =>
    [for (var j = 0; j < count; j++) 'c$c-p$j lorem ipsum dolor'].join('\n\n');

FakeOpenedBook _fakeBook({int chapters = 3, int paragraphs = 40}) =>
    FakeOpenedBook(
      chapters: [
        for (var c = 0; c < chapters; c++) _chapterText(c, paragraphs),
      ],
    );

Widget _app(SimpleReaderEngine engine) => MaterialApp(
  home: Scaffold(body: Builder(builder: engine.buildView)),
);

Future<SimpleReaderEngine> _open(
  WidgetTester tester,
  OpenedBook book, {
  Locator? at,
}) async {
  final engine = SimpleReaderEngine();
  addTearDown(engine.dispose);
  await engine.load(book, at: at);
  await tester.pumpWidget(_app(engine));
  await tester.pump();
  return engine;
}

SelectableText _text(WidgetTester tester, String contains) =>
    tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            (w.textSpan?.toPlainText().contains(contains) ?? false),
      ),
    );

Future<void> _scrollTo(WidgetTester tester, Finder target, double dy) =>
    tester.scrollUntilVisible(
      target,
      dy,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 400,
    );

void main() {
  group('blocks', () {
    testWidgets('paragraphs of a chapter are drawn', (tester) async {
      await _open(tester, _fakeBook());
      expect(find.textContaining('c0-p0 lorem'), findsOneWidget);
      expect(find.textContaining('c0-p1 lorem'), findsOneWidget);
    });

    testWidgets('inline styles, headings, quotes, lists, links', (
      tester,
    ) async {
      final book = _DocBook([
        const ContentDocument([
          HeadingBlock(level: 1, inlines: [TextInline('Title')]),
          ParagraphBlock([
            TextInline('plain '),
            ItalicInline([TextInline('slanted')]),
            TextInline(' '),
            BoldInline([
              TextInline('heavy '),
              ItalicInline([TextInline('both')]),
            ]),
            LinkInline(href: 'x.xhtml', children: [TextInline('linked')]),
          ]),
          QuoteBlock([
            ParagraphBlock([TextInline('quoted')]),
          ]),
          ListBlock(
            ordered: true,
            items: [
              [TextInline('first')],
              [TextInline('second')],
            ],
          ),
          ListBlock(
            ordered: false,
            items: [
              [TextInline('dotted')],
            ],
          ),
        ]),
      ]);
      await _open(tester, book);

      final heading = _text(tester, 'Title');
      final body = _text(tester, 'plain');
      expect(heading.style!.fontWeight, FontWeight.bold);
      expect(heading.style!.fontSize, 36); // 2 x default 18
      expect(body.style!.fontSize, 18);

      TextSpan child(String text) => (body.textSpan!.children!)
          .whereType<TextSpan>()
          .firstWhere((s) => s.toPlainText().startsWith(text));
      expect(child('slanted').style!.fontStyle, FontStyle.italic);
      expect(child('heavy').style!.fontWeight, FontWeight.bold);
      final nested = child('heavy').children!.whereType<TextSpan>().last;
      expect(nested.style!.fontStyle, FontStyle.italic);
      expect(child('linked').style!.decoration, TextDecoration.underline);

      expect(find.text('quoted'), findsOneWidget);
      expect(find.text('first'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('•'), findsOneWidget);
    });

    testWidgets('an image is read through OpenedBook.resource', (tester) async {
      final book = _DocBook(
        [
          const ContentDocument([ImageBlock(src: 'pic.png', alt: 'a picture')]),
        ],
        resources: {'pic.png': Uint8List.fromList(_png)},
      );
      await _open(tester, book);
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a missing image falls back to its alt text', (tester) async {
      final book = _DocBook([
        const ContentDocument([ImageBlock(src: 'gone.png', alt: 'a picture')]),
      ]);
      await _open(tester, book);
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.text('a picture'), findsOneWidget);
    });

    testWidgets('a long chapter is built lazily', (tester) async {
      await _open(tester, _fakeBook(chapters: 1, paragraphs: 500));
      final built = find.byType(SelectableText).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(60));
      expect(find.textContaining('c0-p499'), findsNothing);
    });

    testWidgets('a 15 000-word chapter is lazy and scrolls to its end', (
      tester,
    ) async {
      final paragraph = List.filled(100, 'word').join(' ');
      final text = [for (var p = 0; p < 150; p++) '$paragraph p$p']
          .join('\n\n');
      await _open(tester, FakeOpenedBook(chapters: [text, 'second']));

      final built = find.byType(SelectableText).evaluate().length;
      expect(built, inInclusiveRange(1, 20));

      await _scrollTo(tester, find.text('Next chapter'), 600);
      expect(find.textContaining('p149'), findsOneWidget);
      expect(find.byType(SelectableText).evaluate().length, lessThan(30));
    });

    testWidgets('a book without chapters shows an empty page', (tester) async {
      await _open(tester, _DocBook(const []));
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('Next chapter'), findsNothing);
    });
  });

  group('settings', () {
    testWidgets('font size, family, padding and theme are applied', (
      tester,
    ) async {
      final engine = await _open(tester, _fakeBook());
      expect(_text(tester, 'c0-p0').style!.fontSize, 18);

      engine.applySettings(
        const ReaderSettings(
          fontFamily: 'Georgia',
          fontSize: 24,
          theme: ReaderTheme.dark,
          horizontalPadding: 40,
        ),
      );
      await tester.pump();

      final style = _text(tester, 'c0-p0').style!;
      expect(style.fontSize, 24);
      expect(style.fontFamily, 'Georgia');
      final padding = tester.widget<Padding>(
        find
            .ancestor(
              of: find.textContaining('c0-p0'),
              matching: find.byWidgetPredicate(
                (w) => w is Padding && w.padding is EdgeInsets,
              ),
            )
            .first,
      );
      expect((padding.padding as EdgeInsets).left, 40);
      final background = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(Scaffold),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(background.color, const Color(0xFF121212));
      expect(style.color, const Color(0xFFE0E0E0));

      engine.applySettings(const ReaderSettings());
      await tester.pump();
      expect(_text(tester, 'c0-p0').style!.color, const Color(0xFF212121));
    });

    testWidgets('applying settings keeps the scroll position', (tester) async {
      final engine = await _open(tester, _fakeBook(chapters: 1));
      await _scrollTo(tester, find.textContaining('c0-p25'), 300);
      final list = tester.state(find.byType(ScrollablePositionedList));

      engine.applySettings(const ReaderSettings(fontSize: 22));
      await tester.pump();

      expect(tester.state(find.byType(ScrollablePositionedList)), same(list));
      expect(find.textContaining('c0-p25'), findsOneWidget);
      expect(find.textContaining('c0-p0 '), findsNothing);
    });
  });

  group('chapters', () {
    testWidgets('the first chapter has no previous control', (tester) async {
      await _open(tester, _fakeBook());
      expect(find.text('Previous chapter'), findsNothing);
      expect(find.text('Next chapter'), findsNothing); // below the fold
    });

    testWidgets('next at the end of the list opens the next chapter', (
      tester,
    ) async {
      final engine = await _open(tester, _fakeBook());
      final events = <ReaderEvent>[];
      final sub = engine.events.listen(events.add);
      addTearDown(sub.cancel);

      await _scrollTo(tester, find.text('Next chapter'), 400);
      await tester.tap(find.text('Next chapter'));
      await tester.pumpAndSettle();

      expect(find.textContaining('c1-p0 '), findsOneWidget);
      expect(find.textContaining('c0-p'), findsNothing);
      expect(events, [
        const ChapterFinished(ChapterRef(href: 'chapter1.xhtml', index: 0)),
      ]);
      expect(engine.chapter.value!.ref!.index, 1);
    });

    testWidgets('previous at the top opens the end of the previous chapter', (
      tester,
    ) async {
      final engine = await _open(
        tester,
        _fakeBook(),
        at: const Locator(
          book: _bookId,
          chapter: ChapterRef(href: 'chapter2.xhtml', index: 1),
          progression: 0,
        ),
      );
      expect(find.textContaining('c1-p0 '), findsOneWidget);

      await _scrollTo(tester, find.text('Previous chapter'), -400);
      await tester.tap(find.text('Previous chapter'));
      await tester.pumpAndSettle();

      expect(engine.chapter.value!.ref!.index, 0);
      expect(find.textContaining('c0-p39'), findsOneWidget);
      expect(find.textContaining('c0-p0 '), findsNothing);
    });

    testWidgets('the last chapter has no next control', (tester) async {
      await _open(
        tester,
        _fakeBook(),
        at: const Locator(
          book: _bookId,
          chapter: ChapterRef(href: 'chapter3.xhtml', index: 2),
          progression: 1,
        ),
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pump();
      expect(find.textContaining('c2-p39'), findsOneWidget);
      expect(find.text('Next chapter'), findsNothing);
      expect(find.text('Previous chapter'), findsNothing);
    });

    testWidgets('load(at) starts near the progression of the chapter', (
      tester,
    ) async {
      await _open(
        tester,
        _fakeBook(chapters: 1),
        at: const Locator(
          book: _bookId,
          chapter: ChapterRef(href: 'chapter1.xhtml', index: 0),
          progression: 0.5,
        ),
      );
      expect(find.textContaining('c0-p20 '), findsOneWidget);
      expect(find.textContaining('c0-p0 '), findsNothing);
    });

    testWidgets('goTo switches chapter and position', (tester) async {
      final engine = await _open(tester, _fakeBook());
      await engine.goTo(
        const Locator(
          book: _bookId,
          chapter: ChapterRef(href: 'chapter3.xhtml', index: 2),
          progression: 0.5,
        ),
      );
      await tester.pump();
      expect(engine.chapter.value!.ref!.index, 2);
      expect(find.textContaining('c2-p20 '), findsOneWidget);
    });

    testWidgets('a failing chapter keeps the current one and says so', (
      tester,
    ) async {
      final book = _FailingBook(_fakeBook());
      final engine = await _open(tester, book);
      await _scrollTo(tester, find.text('Next chapter'), 400);
      await tester.tap(find.text('Next chapter'));
      await tester.pumpAndSettle();

      expect(engine.chapter.value!.ref!.index, 0);
      expect(find.text('Could not open the chapter'), findsOneWidget);
    });
  });

  group('lifecycle', () {
    test('dispose closes events and is safe to call twice', () async {
      final engine = SimpleReaderEngine();
      final done = engine.events.toList();
      await engine.dispose();
      await engine.dispose();
      expect(await done, isEmpty);
    });

    test('goTo before load is a programming error', () {
      final engine = SimpleReaderEngine();
      addTearDown(engine.dispose);
      expect(
        () => engine.goTo(
          const Locator(
            book: _bookId,
            chapter: ChapterRef(href: 'c.xhtml', index: 0),
            progression: 0,
          ),
        ),
        throwsStateError,
      );
    });

    test('highlight replaces the previous set', () async {
      final engine = SimpleReaderEngine();
      addTearDown(engine.dispose);
      const a = Locator(
        book: _bookId,
        chapter: ChapterRef(href: 'c.xhtml', index: 0),
        progression: 0.1,
      );
      engine.highlight([a]);
      expect(engine.highlights, [a]);
      engine.highlight(const []);
      expect(engine.highlights, isEmpty);
    });
  });
}

/// Delegates to a book but fails to open chapters after the first.
class _FailingBook implements OpenedBook {
  new(this._inner);

  final OpenedBook _inner;

  @override
  List<ChapterRef> get spine => _inner.spine;

  @override
  List<TocEntry> get toc => _inner.toc;

  @override
  Future<ContentDocument> chapter(ChapterRef ref) => ref.index == 0
      ? _inner.chapter(ref)
      : Future.error(const FormatException('broken chapter'));

  @override
  Future<Uint8List> resource(String href) => _inner.resource(href);

  @override
  Future<void> close() => _inner.close();
}
