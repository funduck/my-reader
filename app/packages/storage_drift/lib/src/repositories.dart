import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:drift/drift.dart';

import 'database.dart';
import 'tables.dart';

/// [BookRepository] on top of `AppDatabase`.
final class DriftBookRepository implements BookRepository {
  /// Creates a repository over the database.
  new(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Book>> watchAll() {
    final query = _db.select(_db.books)
      ..orderBy([
        (t) => OrderingTerm.desc(t.addedAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return query.watch().map((rows) => rows.map(_toBook).toList());
  }

  @override
  Future<Book?> get(BookId id) async {
    final row = await (_db.select(
      _db.books,
    )..where((t) => t.id.equals(id.value))).getSingleOrNull();
    return row == null ? null : _toBook(row);
  }

  @override
  Future<Book?> findByContentHash(String contentHash) async {
    final row =
        await (_db.select(_db.books)
              ..where((t) => t.contentHash.equals(contentHash))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toBook(row);
  }

  @override
  Future<void> save(Book book) => _db
      .into(_db.books)
      .insertOnConflictUpdate(
        BooksCompanion.insert(
          id: book.id.value,
          title: book.metadata.title,
          author: Value(book.metadata.author),
          language: Value(book.metadata.language),
          format: book.format,
          filePath: book.filePath,
          contentHash: book.contentHash,
          addedAt: book.addedAt,
        ),
      );

  @override
  Future<void> remove(BookId id) => _db.transaction(() async {
    await (_db.delete(
      _db.readingProgressTable,
    )..where((t) => t.bookId.equals(id.value))).go();
    await (_db.delete(
      _db.cheatSheetSnapshots,
    )..where((t) => t.bookId.equals(id.value))).go();
    await (_db.delete(_db.books)..where((t) => t.id.equals(id.value))).go();
  });

  Book _toBook(BookRow row) => Book(
    id: BookId(row.id),
    metadata: BookMetadata(
      title: row.title,
      author: row.author,
      language: row.language,
    ),
    format: row.format,
    filePath: row.filePath,
    contentHash: row.contentHash,
    addedAt: row.addedAt,
  );
}

/// [ProgressRepository] on top of `AppDatabase`.
final class DriftProgressRepository implements ProgressRepository {
  /// Creates a repository over the database.
  new(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$ReadingProgressTableTable, ProgressRow> _select(
    BookId book,
  ) =>
      _db.select(_db.readingProgressTable)
        ..where((t) => t.bookId.equals(book.value));

  @override
  Future<ReadingProgress?> get(BookId book) async {
    final row = await _select(book).getSingleOrNull();
    return row == null ? null : _toProgress(row);
  }

  @override
  Stream<ReadingProgress?> watch(BookId book) =>
      _select(book)
          .watchSingleOrNull()
          .map((row) => row == null ? null : _toProgress(row))
          .distinct();

  @override
  Future<void> save(ReadingProgress progress) => _db
      .into(_db.readingProgressTable)
      .insertOnConflictUpdate(
        ReadingProgressTableCompanion.insert(
          bookId: progress.locator.book.value,
          locator: progress.locator,
          percent: progress.percent,
          updatedAt: progress.updatedAt,
        ),
      );

  ReadingProgress _toProgress(ProgressRow row) => ReadingProgress(
    locator: row.locator,
    percent: row.percent,
    updatedAt: row.updatedAt,
  );
}

/// [ProfileRepository] on top of `AppDatabase`.
final class DriftProfileRepository implements ProfileRepository {
  /// Creates a repository over the database.
  new(this._db);

  final AppDatabase _db;

  SimpleSelectStatement<$ProfileTableTable, ProfileRow> _select() =>
      _db.select(_db.profileTable)..where((t) => t.id.equals(singleRowId));

  @override
  Future<UserProfile> get() async =>
      (await _select().getSingleOrNull())?.data ?? const UserProfile();

  @override
  Stream<UserProfile> watch() => _select()
      .watchSingleOrNull()
      .map((row) => row?.data ?? const UserProfile())
      .distinct();

  @override
  Future<void> save(UserProfile profile) => _db
      .into(_db.profileTable)
      .insertOnConflictUpdate(
        ProfileTableCompanion.insert(
          id: const Value(singleRowId),
          data: profile,
        ),
      );

  /// Runs in a transaction; drift runs transactions of a database one at a
  /// time, so concurrent updates do not overwrite each other.
  @override
  Future<UserProfile> update(UserProfile Function(UserProfile) change) =>
      _db.transaction(() async {
        final next = change(await get());
        await save(next);
        return next;
      });
}

/// [LookupJournal] on top of `AppDatabase`.
///
/// Events are listed newest first; among equal times the later record comes
/// first. The `level` filter matches events linked (through `term_events`) to a
/// term that has exactly that level.
final class DriftLookupJournal implements LookupJournal {
  /// Creates a journal over the database.
  new(this._db);

  final AppDatabase _db;

  @override
  Future<void> record(LookupEvent event) async {
    final locator = event.query.locator;
    await _db
        .into(_db.lookupEvents)
        .insert(
          LookupEventsCompanion.insert(
            id: event.id.value,
            at: event.at,
            queryText: event.query.text,
            mode: event.query.mode,
            sentence: Value(event.query.sentence),
            locator: Value(locator),
            bookId: Value(locator?.book.value),
            chapterHref: Value(locator?.chapter.href),
            chapterIndex: Value(locator?.chapter.index),
            provider: event.result.provider.value,
            transcription: Value(event.result.transcription),
            senses: event.result.senses,
          ),
        );
  }

  @override
  Future<LookupEvent?> get(LookupEventId id) async {
    final row = await (_db.select(
      _db.lookupEvents,
    )..where((t) => t.id.equals(id.value))).getSingleOrNull();
    return row == null ? null : _toEvent(row);
  }

  @override
  Stream<List<LookupEvent>> watch([
    LookupFilter filter = const LookupFilter(),
  ]) {
    final query = _db.select(_db.lookupEvents)
      ..where((t) => _matches(t, filter))
      ..orderBy(_newestFirst);
    return query.watch().map((rows) => rows.map(_toEvent).toList());
  }

  /// Returns the events linked to the term [id], newest first.
  Future<List<LookupEvent>> byTerm(TermId id) async {
    final linked = _db.selectOnly(_db.termEvents)
      ..addColumns([_db.termEvents.eventId])
      ..where(_db.termEvents.termId.equals(id.value));
    final rows =
        await (_db.select(_db.lookupEvents)
              ..where((t) => t.id.isInQuery(linked))
              ..orderBy(_newestFirst))
            .get();
    return rows.map(_toEvent).toList();
  }

  List<OrderingTerm Function($LookupEventsTable)> get _newestFirst => [
    (t) => OrderingTerm.desc(t.at),
    (t) => OrderingTerm.desc(CustomExpression<int>('${t.aliasedName}.rowid')),
  ];

  Expression<bool> _matches($LookupEventsTable t, LookupFilter f) {
    final conditions = <Expression<bool>>[
      if (f.book != null) t.bookId.equals(f.book!.value),
      if (f.chapter != null) ...[
        t.chapterHref.equals(f.chapter!.href),
        t.chapterIndex.equals(f.chapter!.index),
      ],
      if (f.from != null)
        t.at.isBiggerOrEqualValue(f.from!.microsecondsSinceEpoch),
      if (f.to != null) t.at.isSmallerThanValue(f.to!.microsecondsSinceEpoch),
      if (f.level != null) _hasTermLevel(t, f.level!),
    ];
    return conditions.fold(const Constant(true), (a, b) => a & b);
  }

  Expression<bool> _hasTermLevel($LookupEventsTable t, CefrLevel level) {
    final subquery = _db.selectOnly(_db.termEvents)
      ..join([
        innerJoin(_db.terms, _db.terms.id.equalsExp(_db.termEvents.termId)),
      ])
      ..addColumns([_db.termEvents.eventId])
      ..where(
        _db.termEvents.eventId.equalsExp(t.id) &
            _db.terms.level.equals(level.name),
      );
    return existsQuery(subquery);
  }

  LookupEvent _toEvent(LookupEventRow row) => LookupEvent(
    id: LookupEventId(row.id),
    query: LookupQuery(
      text: row.queryText,
      mode: row.mode,
      sentence: row.sentence,
      locator: row.locator,
    ),
    result: LookupResult(
      provider: ProviderId(row.provider),
      senses: row.senses,
      transcription: row.transcription,
    ),
    at: row.at,
  );
}

/// [PhraseJournal] on top of `AppDatabase`.
///
/// Entries are listed newest first; among equal times the later record comes
/// first.
final class DriftPhraseJournal implements PhraseJournal {
  /// Creates a journal over the database.
  new(this._db);

  final AppDatabase _db;

  @override
  Future<void> record(PhraseLookup phrase) async {
    await _db
        .into(_db.phraseLookups)
        .insert(
          PhraseLookupsCompanion.insert(
            id: phrase.id.value,
            phrase: phrase.text,
            translation: phrase.translation,
            provider: phrase.provider.value,
            at: phrase.at,
            locator: phrase.locator,
            bookId: phrase.locator.book.value,
            sentence: Value(phrase.sentence),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Stream<List<PhraseLookup>> watchAll() =>
      _newestFirst(_db.select(_db.phraseLookups))
          .watch()
          .map((rows) => rows.map(_toPhrase).toList());

  @override
  Future<List<PhraseLookup>> byBook(BookId book) async {
    final rows = await _newestFirst(
      _db.select(_db.phraseLookups)..where((t) => t.bookId.equals(book.value)),
    ).get();
    return rows.map(_toPhrase).toList();
  }

  @override
  Future<void> delete(PhraseLookupId id) async {
    await (_db.delete(
      _db.phraseLookups,
    )..where((t) => t.id.equals(id.value))).go();
  }

  SimpleSelectStatement<$PhraseLookupsTable, PhraseLookupRow> _newestFirst(
    SimpleSelectStatement<$PhraseLookupsTable, PhraseLookupRow> query,
  ) => query
    ..orderBy([
      (t) => OrderingTerm.desc(t.at),
      (t) => OrderingTerm.desc(CustomExpression<int>('${t.aliasedName}.rowid')),
    ]);

  PhraseLookup _toPhrase(PhraseLookupRow row) => PhraseLookup(
    id: PhraseLookupId(row.id),
    text: row.phrase,
    translation: row.translation,
    provider: ProviderId(row.provider),
    at: row.at,
    locator: row.locator,
    sentence: row.sentence,
  );
}

/// [CheatSheetLog] on top of `AppDatabase`: one row per book, replaced on save.
final class DriftCheatSheetLog implements CheatSheetLog {
  /// Creates a log over the database.
  new(this._db);

  final AppDatabase _db;

  @override
  Future<void> save(CheatSheetSnapshot snapshot) => _db
      .into(_db.cheatSheetSnapshots)
      .insertOnConflictUpdate(
        CheatSheetSnapshotsCompanion.insert(
          bookId: snapshot.book.value,
          shownAt: snapshot.shownAt,
          lemmas: snapshot.lemmas,
        ),
      );

  @override
  Stream<CheatSheetSnapshot?> watch(BookId book) =>
      (_db.select(_db.cheatSheetSnapshots)
            ..where((t) => t.bookId.equals(book.value)))
          .watchSingleOrNull()
          .map(
            (row) => row == null
                ? null
                : CheatSheetSnapshot(
                    book: BookId(row.bookId),
                    shownAt: row.shownAt,
                    lemmas: row.lemmas,
                  ),
          )
          // drift re-runs the query on any change of the table.
          .distinct();
}

/// [TermRepository] on top of `AppDatabase`.
final class DriftTermRepository implements TermRepository {
  /// Creates a repository over the database.
  new(this._db);

  final AppDatabase _db;

  @override
  Future<Term?> find(String normalized, String language) async {
    final row =
        await (_db.select(_db.terms)..where(
              (t) =>
                  t.normalized.equals(normalized) & t.language.equals(language),
            ))
            .getSingleOrNull();
    return row == null ? null : (await _withEvents([row])).single;
  }

  /// Returns the term with the lemma [lemma] in [language], or null.
  Future<Term?> byLemma(String lemma, {String language = 'en'}) =>
      find(lemma, language);

  /// Returns the lemmas of all terms in [language], optionally only those
  /// with [status]; for filtering the cheat sheet.
  Future<Set<String>> allLemmas({
    String language = 'en',
    TermStatus? status,
  }) async {
    final query = _db.selectOnly(_db.terms)
      ..addColumns([_db.terms.normalized])
      ..where(
        _db.terms.language.equals(language) &
            (status == null
                ? const Constant(true)
                : _db.terms.status.equals(status.name)),
      );
    final rows = await query.get();
    return {for (final row in rows) row.read(_db.terms.normalized)!};
  }

  @override
  Stream<List<Term>> watchAll({TermStatus? status}) {
    final query = _db.select(_db.terms)
      ..where(
        (t) => status == null
            ? const Constant(true)
            : t.status.equals(status.name),
      )
      ..orderBy([
        (t) =>
            OrderingTerm.asc(CustomExpression<int>('${t.aliasedName}.rowid')),
      ]);
    return query.watch().asyncMap(_withEvents);
  }

  @override
  Future<void> save(Term term) => _db.transaction(() async {
    await _db
        .into(_db.terms)
        .insertOnConflictUpdate(
          TermsCompanion.insert(
            id: term.id.value,
            normalized: term.normalized,
            language: term.language,
            lookupCount: term.lookupCount,
            status: term.status,
            level: term.level,
          ),
        );
    await (_db.delete(
      _db.termEvents,
    )..where((t) => t.termId.equals(term.id.value))).go();
    await _db.batch((batch) {
      batch.insertAll(_db.termEvents, [
        for (final (i, event) in term.eventIds.indexed)
          TermEventsCompanion.insert(
            termId: term.id.value,
            eventId: event.value,
            position: i,
          ),
      ]);
    });
  });

  /// Registers one more lookup of [lemma]: creates the term with [id] if there
  /// is none, otherwise increments the counter of the existing one (its own id
  /// stays). The [event] is appended to the term's events and [level] replaces
  /// the stored one when known. Returns the saved term.
  Future<Term> upsert({
    required TermId id,
    required String lemma,
    required String language,
    required LookupEventId event,
    CefrLevel level = CefrLevel.unknown,
  }) => _db.transaction(() async {
    final existing = await find(lemma, language);
    final term = existing == null
        ? Term(
            id: id,
            normalized: lemma,
            language: language,
            lookupCount: 1,
            eventIds: [event],
            level: level,
          )
        : existing.copyWith(
            lookupCount: existing.lookupCount + 1,
            eventIds: [...existing.eventIds, event],
            level: level.isKnown ? level : existing.level,
          );
    await save(term);
    return term;
  });

  Future<List<Term>> _withEvents(List<TermRow> rows) async {
    if (rows.isEmpty) return const [];
    final links =
        await (_db.select(_db.termEvents)..orderBy([
              (t) => OrderingTerm.asc(t.termId),
              (t) => OrderingTerm.asc(t.position),
            ]))
            .get();
    final byTerm = <String, List<LookupEventId>>{};
    for (final link in links) {
      (byTerm[link.termId] ??= []).add(LookupEventId(link.eventId));
    }
    return [
      for (final row in rows)
        Term(
          id: TermId(row.id),
          normalized: row.normalized,
          language: row.language,
          lookupCount: row.lookupCount,
          eventIds: byTerm[row.id] ?? const [],
          status: row.status,
          level: row.level,
        ),
    ];
  }
}
