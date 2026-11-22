import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

/// A book file the adapter must open, with what it must read from it.
class BookFixture {
  /// Creates a fixture: the file at [path] has [metadata] and at least
  /// [minChapters] chapters in the spine.
  const new({required this.path, required this.metadata, this.minChapters = 1});

  /// Absolute path of the file.
  final String path;

  /// Expected metadata. Only fields that are not null are compared, the
  /// title always.
  final BookMetadata metadata;

  /// Lower bound of `spine.length`.
  final int minChapters;
}

/// Files for [formatAdapterContract].
class FormatFixtures {
  /// Creates the set: [valid] books and [invalid] paths (broken, foreign or
  /// missing files).
  const new({required this.valid, required this.invalid});

  /// Books that open.
  final List<BookFixture> valid;

  /// Paths that are not books of this adapter.
  final List<String> invalid;
}

/// Behaviour every [BookFormatAdapter] must have.
///
/// [create] returns the adapter, already able to serve [fixtures] (the fake
/// registers them; a real adapter reads the files).
void formatAdapterContract(
  FutureOr<BookFormatAdapter> Function() create,
  FormatFixtures fixtures,
) {
  group('BookFormatAdapter contract', () {
    late BookFormatAdapter adapter;

    setUp(() async => adapter = await create());

    test('declares at least one format', () {
      expect(adapter.formats, isNotEmpty);
    });

    for (final fx in fixtures.valid) {
      group('valid ${fx.path}', () {
        test('canOpen is true', () async {
          expect(await adapter.canOpen(fx.path), isTrue);
        });

        test('readMetadata returns the expected metadata', () async {
          final meta = await adapter.readMetadata(fx.path);
          expect(meta.title, fx.metadata.title);
          if (fx.metadata.author != null) {
            expect(meta.author, fx.metadata.author);
          }
          if (fx.metadata.language != null) {
            expect(meta.language, fx.metadata.language);
          }
        });

        test('open gives a spine whose chapters can be read', () async {
          final book = await adapter.open(fx.path);
          addTearDown(book.close);
          expect(book.spine.length, greaterThanOrEqualTo(fx.minChapters));
          for (var i = 0; i < book.spine.length; i++) {
            expect(book.spine[i].index, i, reason: 'spine index');
          }
          var blocks = 0;
          for (final ref in book.spine) {
            blocks += (await book.chapter(ref)).blocks.length;
          }
          expect(blocks, greaterThan(0), reason: 'the book has some content');
        });

        test('toc entries point into the spine', () async {
          final book = await adapter.open(fx.path);
          addTearDown(book.close);
          final indexes = {for (final c in book.spine) c.index};
          void check(List<TocEntry> entries) {
            for (final e in entries) {
              expect(indexes, contains(e.chapter.index), reason: e.title);
              check(e.children);
            }
          }

          check(book.toc);
        });

        test('close can be called', () async {
          final book = await adapter.open(fx.path);
          await book.close();
        });
      });
    }

    for (final path in fixtures.invalid) {
      group('invalid $path', () {
        test('canOpen is false and does not throw', () async {
          expect(await adapter.canOpen(path), isFalse);
        });

        test('readMetadata throws FormatException', () async {
          await expectLater(
            adapter.readMetadata(path),
            throwsA(isA<FormatException>()),
          );
        });

        test('open throws FormatException', () async {
          await expectLater(
            adapter.open(path),
            throwsA(isA<FormatException>()),
          );
        });
      });
    }
  });
}
