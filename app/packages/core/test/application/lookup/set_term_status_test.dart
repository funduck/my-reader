import 'package:core/application.dart';
import 'package:core/domain_lookup.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Counts writes, to tell "changed nothing" from "wrote the same value".
class _CountingTerms extends MemoryTerms {
  int saves = 0;

  @override
  Future<void> save(Term term) {
    saves++;
    return super.save(term);
  }
}

void main() {
  late _CountingTerms terms;
  late MapLevels levels;
  late SetTermStatus setStatus;

  setUp(() {
    terms = _CountingTerms();
    levels = MapLevels({'run': CefrLevel.a2});
    setStatus = SetTermStatus(terms: terms, levels: levels, ids: CountingIds());
  });

  test(
    'a new term gets the status, no lookups and the dictionary level',
    () async {
      final term = await setStatus('run', TermStatus.known);
      expect(term.normalized, 'run');
      expect(term.language, 'en');
      expect(term.status, TermStatus.known);
      expect(term.lookupCount, 0);
      expect(term.eventIds, isEmpty);
      expect(term.level, CefrLevel.a2);
      expect(await terms.find('run', 'en'), term);
    },
  );

  test('a word without a level gets an unknown level', () async {
    final term = await setStatus('zzz', TermStatus.known);
    expect(term.level, CefrLevel.unknown);
  });

  test('an existing term changes only its status', () async {
    const existing = Term(
      id: TermId('t1'),
      normalized: 'run',
      language: 'en',
      lookupCount: 3,
      eventIds: [LookupEventId('e1'), LookupEventId('e2')],
      level: CefrLevel.b1,
    );
    await terms.save(existing);
    final term = await setStatus('run', TermStatus.known);
    expect(term, existing.copyWith(status: TermStatus.known));
    expect(term.id, existing.id);
    expect(term.level, CefrLevel.b1);
    expect(terms.terms.values.single, term);
  });

  test('the same status again changes nothing', () async {
    final first = await setStatus('run', TermStatus.known);
    final savesBefore = terms.saves;
    final again = await setStatus('run', TermStatus.known);
    expect(again, first);
    expect(terms.saves, savesBefore);
    expect(terms.terms, hasLength(1));
  });

  test('back to learning keeps the term', () async {
    await setStatus('run', TermStatus.known);
    final term = await setStatus('run', TermStatus.learning);
    expect(term.status, TermStatus.learning);
    expect(terms.terms, hasLength(1));
  });

  test('another language is another term', () async {
    await setStatus('run', TermStatus.known);
    await setStatus('run', TermStatus.known, language: 'de');
    expect(terms.terms, hasLength(2));
  });
}
