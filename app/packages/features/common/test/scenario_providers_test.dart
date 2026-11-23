import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

class _Terms implements TermRepository {
  final Map<TermId, Term> saved = {};

  @override
  Future<Term?> find(String normalized, String language) async => null;

  @override
  Stream<List<Term>> watchAll({TermStatus? status}) =>
      Stream.value(saved.values.toList());

  @override
  Future<void> save(Term term) async => saved[term.id] = term;
}

class _Levels implements LevelDictionary {
  @override
  WordLevel levelOf(String lemma, {String? pos}) =>
      const WordLevel(CefrLevel.b1);
}

class _Ids implements IdGenerator {
  @override
  String newId() => 'id1';
}

void main() {
  test('the scenario needs the ports wired', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(setTermStatusProvider),
      throwsA(anyOf(isA<PortNotWiredError>(), isA<ProviderException>())),
    );
  });

  test('the scenario is built from the ports', () async {
    final terms = _Terms();
    final container = ProviderContainer(
      overrides: [
        termRepositoryProvider.overrideWithValue(terms),
        levelDictionaryProvider.overrideWithValue(_Levels()),
        idGeneratorProvider.overrideWithValue(_Ids()),
      ],
    );
    addTearDown(container.dispose);

    final term = await container.read(setTermStatusProvider)(
      'run',
      TermStatus.known,
    );
    expect(term.status, TermStatus.known);
    expect(term.level, CefrLevel.b1);
    expect(terms.saved.values.single, term);
  });
}
