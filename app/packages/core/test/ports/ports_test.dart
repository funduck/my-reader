import 'dart:typed_data';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

const _bookId = BookId('b1');
const _chapter = ChapterRef(href: 'c1.xhtml', index: 0);
const _locator = Locator(book: _bookId, chapter: _chapter, progression: 0);

class _Adapter implements BookFormatAdapter {
  @override
  Set<BookFormat> get formats => {BookFormat.epub};
  @override
  Future<bool> canOpen(String path) async => path.endsWith('.epub');
  @override
  Future<BookMetadata> readMetadata(String path) async =>
      const BookMetadata(title: 't');
  @override
  Future<OpenedBook> open(String path) async => _Opened();
}

class _Opened implements OpenedBook {
  @override
  List<TocEntry> get toc => const [];
  @override
  List<ChapterRef> get spine => const [_chapter];
  @override
  Future<ContentDocument> chapter(ChapterRef ref) async =>
      const ContentDocument([]);
  @override
  Future<Uint8List> resource(String href) async => Uint8List(0);
  @override
  Future<void> close() async {}
}

class _Provider implements LookupProvider {
  @override
  ProviderId get id => const ProviderId('p');
  @override
  ProviderInfo get info =>
      const ProviderInfo(name: 'p', isOnline: false, modes: {LookupMode.enEn});
  @override
  bool supports(LookupMode mode) => info.modes.contains(mode);
  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) async {
    cancel?.throwIfCancelled();
    if (query.text == 'x') throw const ProviderUnavailable('offline');
    if (query.text == 'y') throw const LookupNotFound();
    return LookupResult(
      provider: id,
      senses: const [Sense(text: 'a thing')],
    );
  }
}

class _Books implements BookRepository {
  @override
  Stream<List<Book>> watchAll() => Stream.value(const []);
  @override
  Future<Book?> get(BookId id) async => null;
  @override
  Future<Book?> findByContentHash(String contentHash) async => null;
  @override
  Future<void> save(Book book) async {}
  @override
  Future<void> remove(BookId id) async {}
}

class _Progress implements ProgressRepository {
  @override
  Future<ReadingProgress?> get(BookId book) async => null;
  @override
  Stream<ReadingProgress?> watch(BookId book) => Stream.value(null);
  @override
  Future<void> save(ReadingProgress progress) async {}
}

class _Journal implements LookupJournal {
  @override
  Future<void> record(LookupEvent event) async {}
  @override
  Future<LookupEvent?> get(LookupEventId id) async => null;
  @override
  Stream<List<LookupEvent>> watch([
    LookupFilter filter = const LookupFilter(),
  ]) => Stream.value(const []);
}

class _Terms implements TermRepository {
  @override
  Future<Term?> find(String normalized, String language) async => null;
  @override
  Stream<List<Term>> watchAll({TermStatus? status}) => Stream.value(const []);
  @override
  Future<void> save(Term term) async {}
}

class _Profiles implements ProfileRepository {
  @override
  Future<UserProfile> get() async => const UserProfile();
  @override
  Stream<UserProfile> watch() => Stream.value(const UserProfile());
  @override
  Future<void> save(UserProfile profile) async {}
}

class _Analyzer implements TextAnalyzer {
  @override
  List<SentenceSpan> sentences(String text) => [SentenceSpan(0, text.length)];
  @override
  List<TextToken> tokens(String text) => [TextToken(text, 0, text.length)];
  @override
  String lemma(String word) => word.toLowerCase();
}

class _Levels implements LevelDictionary {
  @override
  WordLevel levelOf(String lemma, {String? pos}) =>
      const WordLevel(CefrLevel.c1, estimated: true, zipf: 3.2);
}

class _Generator implements CheatSheetGenerator {
  @override
  Future<CheatSheet> generate({
    required String text,
    required Locator from,
    required Locator to,
    required CefrLevel userLevel,
    Set<String> knownTerms = const {},
    CancelToken? cancel,
  }) async => CheatSheet(from: from, to: to, items: const []);
}

class _Packs implements PackStore {
  @override
  Future<List<PackManifestEntry>> manifest() async => const [];
  @override
  Future<List<InstalledPack>> installed() async => const [];
  @override
  Future<InstalledPack> download(String id, PackProgress onProgress) async {
    onProgress(1);
    return InstalledPack(id: id, version: '1');
  }

  @override
  Future<String?> pathOf(String id) async => null;
  @override
  Future<void> remove(String id) async {}
}

class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026);
}

class _Ids implements IdGenerator {
  int _n = 0;
  @override
  String newId() => 'id${_n++}';
}

void main() {
  group('ports are implementable', () {
    test('book format adapter and opened book', () async {
      final adapter = _Adapter();
      expect(await adapter.canOpen('a.epub'), isTrue);
      final book = await adapter.open('a.epub');
      expect(book.spine, hasLength(1));
      await book.close();
    });

    test('lookup provider signals failure with typed exceptions', () async {
      final provider = _Provider();
      LookupQuery q(String t) => LookupQuery(text: t, mode: LookupMode.enEn);
      expect((await provider.lookup(q('a'))).senses, hasLength(1));
      expect(provider.lookup(q('x')), throwsA(isA<ProviderUnavailable>()));
      expect(provider.lookup(q('y')), throwsA(isA<LookupNotFound>()));
      final token = CancelToken()..cancel();
      expect(
        provider.lookup(q('a'), cancel: token),
        throwsA(isA<CancelledException>()),
      );
    });

    test('repositories, journal and profile', () async {
      expect(await _Books().get(_bookId), isNull);
      expect(await _Progress().get(_bookId), isNull);
      expect(await _Journal().watch().first, isEmpty);
      expect(await _Terms().find('a', 'en'), isNull);
      expect((await _Profiles().get()).level, CefrLevel.b2);
    });

    test('analysis, levels and cheat sheet', () async {
      expect(_Analyzer().tokens('Run').single.end, 3);
      final level = _Levels().levelOf('run', pos: 'verb');
      expect(
        (level.level, level.estimated, level.zipf),
        (CefrLevel.c1, true, 3.2),
      );
      final sheet = await _Generator().generate(
        text: '',
        from: _locator,
        to: _locator,
        userLevel: CefrLevel.b1,
      );
      expect(sheet.items, isEmpty);
    });

    test('pack store, clock and id generator', () async {
      double? last;
      final pack = await _Packs().download('en-en', (f) => last = f);
      expect((pack.id, last), ('en-en', 1.0));
      expect(_Clock().now(), DateTime.utc(2026));
      final ids = _Ids();
      expect(ids.newId(), isNot(ids.newId()));
    });
  });

  group('CancelToken', () {
    test('starts not cancelled and does not throw', () {
      final token = CancelToken();
      expect(token.isCancelled, isFalse);
      expect(token.throwIfCancelled, returnsNormally);
    });

    test('cancel is sticky, idempotent and makes throwIfCancelled throw', () {
      final token = CancelToken()
        ..cancel()
        ..cancel();
      expect(token.isCancelled, isTrue);
      expect(token.throwIfCancelled, throwsA(isA<CancelledException>()));
    });
  });

  group('value classes', () {
    test('WordLevel, LookupFilter, PackManifestEntry compare by value', () {
      expect(const WordLevel(CefrLevel.b1), const WordLevel(CefrLevel.b1));
      expect(
        const WordLevel(CefrLevel.b1),
        isNot(const WordLevel(CefrLevel.b1, estimated: true)),
      );
      expect(
        const LookupFilter(book: _bookId),
        const LookupFilter(book: _bookId),
      );
      expect(
        const PackManifestEntry(
          id: 'a',
          version: '1',
          sizeBytes: 1,
          sha256: 'x',
        ),
        const PackManifestEntry(
          id: 'a',
          version: '1',
          sizeBytes: 1,
          sha256: 'x',
        ),
      );
      expect(const TextToken('a', 0, 1), const TextToken('a', 0, 1));
      expect(const SentenceSpan(0, 1), isNot(const SentenceSpan(0, 2)));
    });
  });
}
