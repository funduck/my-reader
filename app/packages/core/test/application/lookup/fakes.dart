// Minimal in-memory ports for the lookup tests.
//
// `core` may not depend on `core_testing` (tool/check_imports.dart), so these
// small fakes live here.
import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';

class ScriptedProvider implements LookupProvider {
  new(
    String id, {
    this.modes = const {LookupMode.enEn, LookupMode.enRu},
    this.answer,
    this.failure,
    this.hang = false,
    this.log,
    this.onCall,
  }) : id = ProviderId(id);

  /// Runs at the start of every call, before the cancel check.
  final void Function()? onCall;

  @override
  final ProviderId id;
  final Set<LookupMode> modes;

  /// Returned by [lookup] when no failure is set.
  LookupResult? answer;
  LookupFailure? failure;

  /// Never answers: the future stays pending.
  final bool hang;

  /// Shared call log (provider id values), to assert order.
  final List<String>? log;
  final List<LookupQuery> calls = [];
  final List<CancelToken?> tokens = [];

  @override
  ProviderInfo get info =>
      ProviderInfo(name: id.value, isOnline: false, modes: modes);

  @override
  bool supports(LookupMode mode) => modes.contains(mode);

  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) async {
    calls.add(query);
    tokens.add(cancel);
    log?.add(id.value);
    onCall?.call();
    cancel?.throwIfCancelled();
    if (hang) await Completer<void>().future;
    final failure = this.failure;
    if (failure != null) throw failure;
    return answer ?? (throw const LookupNotFound());
  }
}

LookupResult result(String provider, [List<String> senses = const ['x']]) =>
    LookupResult(
      provider: ProviderId(provider),
      senses: [for (final s in senses) Sense(text: s)],
    );

class MemoryProfiles implements ProfileRepository {
  new([this.profile = const UserProfile()]);

  UserProfile profile;

  @override
  Future<UserProfile> get() async => profile;

  @override
  Stream<UserProfile> watch() => Stream.value(profile);

  @override
  Future<void> save(UserProfile profile) async => this.profile = profile;

  @override
  Future<UserProfile> update(UserProfile Function(UserProfile) change) async {
    final next = change(await get());
    await save(next);
    return next;
  }
}

class MemoryJournal implements LookupJournal {
  final List<LookupEvent> events = [];

  @override
  Future<void> record(LookupEvent event) async => events.add(event);

  @override
  Future<LookupEvent?> get(LookupEventId id) async {
    for (final e in events) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Stream<List<LookupEvent>> watch([
    LookupFilter filter = const LookupFilter(),
  ]) => Stream.value(List.of(events));
}

class MemoryTerms implements TermRepository {
  final Map<TermId, Term> terms = {};

  @override
  Future<Term?> find(String normalized, String language) async {
    for (final t in terms.values) {
      if (t.normalized == normalized && t.language == language) return t;
    }
    return null;
  }

  @override
  Stream<List<Term>> watchAll({TermStatus? status}) =>
      Stream.value(terms.values.toList());

  @override
  Future<void> save(Term term) async => terms[term.id] = term;
}

class FixedClock implements Clock {
  new(this.time);

  DateTime time;

  @override
  DateTime now() => time;
}

class CountingIds implements IdGenerator {
  int _n = 0;

  @override
  String newId() => 'id${++_n}';
}

/// Splits on whitespace; lemma strips a trailing `s` and lower-cases.
class SimpleAnalyzer implements TextAnalyzer {
  @override
  List<SentenceSpan> sentences(String text) => [SentenceSpan(0, text.length)];

  @override
  List<TextToken> tokens(String text) => [
    for (final m in RegExp('[A-Za-z]+').allMatches(text))
      TextToken(m[0]!, m.start, m.end),
  ];

  @override
  String lemma(String word) {
    final w = word.toLowerCase();
    return w.endsWith('s') ? w.substring(0, w.length - 1) : w;
  }
}

class MapLevels implements LevelDictionary {
  new([this.levels = const {}, this.estimated = const {}]);

  final Map<String, CefrLevel> levels;

  /// Keys whose level counts as derived from frequency.
  final Set<String> estimated;

  /// Keys asked, in order.
  final List<String> asked = [];

  @override
  WordLevel levelOf(String lemma, {String? pos}) {
    asked.add(lemma);
    return WordLevel(
      levels[lemma] ?? CefrLevel.unknown,
      estimated: estimated.contains(lemma),
    );
  }
}
