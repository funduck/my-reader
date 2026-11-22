import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

/// Behaviour every [LookupProvider] must have.
///
/// [create] returns a working provider; it may register cleanup with
/// `addTearDown`. [known] is a query the provider has an entry for, [unknown]
/// one it has no entry for. [createUnavailable], if given, returns a provider
/// that cannot answer now (offline, pack missing); the suite then checks that
/// it throws [ProviderUnavailable].
void lookupProviderContract(
  FutureOr<LookupProvider> Function() create, {
  required LookupQuery known,
  required LookupQuery unknown,
  FutureOr<LookupProvider> Function()? createUnavailable,
}) {
  group('LookupProvider contract', () {
    late LookupProvider provider;

    setUp(() async => provider = await create());

    test('info is consistent with supports()', () {
      expect(provider.info.name, isNotEmpty);
      expect(provider.info.modes, isNotEmpty);
      for (final mode in LookupMode.values) {
        expect(
          provider.supports(mode),
          provider.info.modes.contains(mode),
          reason: '$mode',
        );
      }
    });

    test('supports the mode of the known query', () {
      expect(provider.supports(known.mode), isTrue);
    });

    test('a known query returns senses attributed to this provider', () async {
      final result = await provider.lookup(known);
      expect(result.provider, provider.id);
      expect(result.senses, isNotEmpty);
      for (final sense in result.senses) {
        expect(sense.text, isNotEmpty);
      }
    });

    test('an unknown query throws LookupNotFound', () async {
      await expectLater(
        provider.lookup(unknown),
        throwsA(isA<LookupNotFound>()),
      );
    });

    test('a token cancelled beforehand throws CancelledException', () async {
      final cancel = CancelToken()..cancel();
      await expectLater(
        provider.lookup(known, cancel: cancel),
        throwsA(isA<CancelledException>()),
      );
    });

    test('an untouched token does not disturb the answer', () async {
      final result = await provider.lookup(known, cancel: CancelToken());
      expect(result.senses, isNotEmpty);
    });

    if (createUnavailable != null) {
      test('an unavailable provider throws ProviderUnavailable', () async {
        final broken = await createUnavailable();
        await expectLater(
          broken.lookup(known),
          throwsA(isA<ProviderUnavailable>()),
        );
      });
    }
  });
}
