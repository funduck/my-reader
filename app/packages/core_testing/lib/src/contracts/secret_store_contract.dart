import 'dart:async';

import 'package:core/ports.dart';
import 'package:test/test.dart';

/// Behaviour every [SecretStore] must have.
///
/// [create] returns a fresh store with nothing saved for each test.
void secretStoreContract(FutureOr<SecretStore> Function() create) {
  group('SecretStore contract', () {
    late SecretStore store;

    setUp(() async => store = await create());

    test('read of a missing key returns null', () async {
      expect(await store.read('missing'), isNull);
    });

    test('write then read returns the value', () async {
      await store.write(deeplApiKey, 'secret-1234');
      expect(await store.read(deeplApiKey), 'secret-1234');
    });

    test('writing again replaces the value', () async {
      await store.write('k', 'one');
      await store.write('k', 'two');
      expect(await store.read('k'), 'two');
    });

    test('write of null removes the value', () async {
      await store.write('k', 'one');
      await store.write('k', null);
      expect(await store.read('k'), isNull);
    });

    test('removing a missing key does not fail', () async {
      await store.write('missing', null);
      expect(await store.read('missing'), isNull);
    });

    test('keys are independent', () async {
      await store.write('a', '1');
      await store.write('b', '2');
      await store.write('a', null);
      expect(await store.read('a'), isNull);
      expect(await store.read('b'), '2');
    });
  });
}
