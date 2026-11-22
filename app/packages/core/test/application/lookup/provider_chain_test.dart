import 'package:core/application.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _query = LookupQuery(text: 'run', mode: LookupMode.enEn);

ChainSuccess _success(ChainResult r) => r as ChainSuccess;

ChainFailure _failure(ChainResult r) => r as ChainFailure;

void main() {
  late List<String> log;
  late MemoryProfiles profiles;

  setUp(() {
    log = [];
    profiles = MemoryProfiles();
  });

  ProviderChain chain(
    List<LookupProvider> providers, {
    Duration timeout = const Duration(milliseconds: 20),
  }) =>
      ProviderChain(providers: providers, profiles: profiles, timeout: timeout);

  test('default timeout is 5 seconds', () {
    expect(ProviderChain.defaultTimeout, const Duration(seconds: 5));
    expect(
      ProviderChain(providers: const [], profiles: profiles).timeout,
      const Duration(seconds: 5),
    );
  });

  group('fallback', () {
    test('first provider answers: the rest are not called', () async {
      final a = ScriptedProvider('a', answer: result('a'), log: log);
      final b = ScriptedProvider('b', answer: result('b'), log: log);
      final r = _success(await chain([a, b]).lookup(_query));
      expect(r.result.provider, const ProviderId('a'));
      expect(r.failedBefore, isEmpty);
      expect(log, ['a']);
    });

    test('goes to the next on ProviderUnavailable', () async {
      final a = ScriptedProvider(
        'a',
        failure: const ProviderUnavailable(),
        log: log,
      );
      final b = ScriptedProvider('b', answer: result('b'), log: log);
      final r = _success(await chain([a, b]).lookup(_query));
      expect(r.result.provider, const ProviderId('b'));
      expect(r.failedBefore, [
        const ProviderAttempt(ProviderId('a'), AttemptFailure.unavailable),
      ]);
      expect(log, ['a', 'b']);
    });

    test('goes to the next on LookupNotFound', () async {
      final a = ScriptedProvider('a', failure: const LookupNotFound());
      final b = ScriptedProvider('b', answer: result('b'));
      final r = _success(await chain([a, b]).lookup(_query));
      expect(r.failedBefore.single.failure, AttemptFailure.notFound);
    });

    test('goes to the next on an empty answer', () async {
      final a = ScriptedProvider('a', answer: result('a', const []));
      final b = ScriptedProvider('b', answer: result('b'));
      final r = _success(await chain([a, b]).lookup(_query));
      expect(r.result.provider, const ProviderId('b'));
      expect(r.failedBefore, [
        const ProviderAttempt(ProviderId('a'), AttemptFailure.empty),
      ]);
    });

    test('all fail: ChainFailure lists every attempt in order', () async {
      final a = ScriptedProvider('a', failure: const ProviderUnavailable());
      final b = ScriptedProvider('b', answer: result('b', const []));
      final c = ScriptedProvider('c', failure: const LookupNotFound());
      final f = _failure(await chain([a, b, c]).lookup(_query));
      expect(f.attempts, [
        const ProviderAttempt(ProviderId('a'), AttemptFailure.unavailable),
        const ProviderAttempt(ProviderId('b'), AttemptFailure.empty),
        const ProviderAttempt(ProviderId('c'), AttemptFailure.notFound),
      ]);
      expect(f.isNotFound, isFalse);
    });

    test('isNotFound when everybody found nothing', () async {
      final a = ScriptedProvider('a', failure: const LookupNotFound());
      final b = ScriptedProvider('b', answer: result('b', const []));
      expect(_failure(await chain([a, b]).lookup(_query)).isNotFound, isTrue);
    });

    test('no providers at all: empty failure, not "not found"', () async {
      final f = _failure(await chain([]).lookup(_query));
      expect(f.attempts, isEmpty);
      expect(f.isNotFound, isFalse);
    });

    test('a non-LookupFailure exception is a bug and propagates', () async {
      final a = ScriptedProvider('a', onCall: () => throw StateError('bug'));
      await expectLater(chain([a]).lookup(_query), throwsStateError);
    });
  });

  group('timeout', () {
    test('a provider that never answers is skipped', () async {
      final a = ScriptedProvider('a', hang: true, log: log);
      final b = ScriptedProvider('b', answer: result('b'), log: log);
      final r = _success(
        await chain([
          a,
          b,
        ], timeout: const Duration(milliseconds: 5)).lookup(_query),
      );
      expect(r.result.provider, const ProviderId('b'));
      expect(r.failedBefore, [
        const ProviderAttempt(ProviderId('a'), AttemptFailure.timedOut),
      ]);
    });

    test('timeout applies per provider, not to the whole chain', () async {
      final a = ScriptedProvider('a', hang: true);
      final b = ScriptedProvider('b', hang: true);
      final f = _failure(
        await chain([
          a,
          b,
        ], timeout: const Duration(milliseconds: 5)).lookup(_query),
      );
      expect(f.attempts.map((x) => x.failure), [
        AttemptFailure.timedOut,
        AttemptFailure.timedOut,
      ]);
    });
  });

  group('order and mode', () {
    test('empty profile order means registration order', () async {
      final order = <String>[];
      final pa = ScriptedProvider('a', log: order);
      final pb = ScriptedProvider('b', log: order);
      await chain([pa, pb]).lookup(_query);
      expect(order, ['a', 'b']);
    });

    test('order comes from the profile', () async {
      profiles.profile = const UserProfile(
        providerOrder: [ProviderId('c'), ProviderId('a')],
      );
      final order = <String>[];
      final pa = ScriptedProvider('a', log: order);
      final pb = ScriptedProvider('b', log: order);
      final pc = ScriptedProvider('c', log: order);
      await chain([pa, pb, pc]).lookup(_query);
      // Listed ids first, in the listed order, then the unlisted one.
      expect(order, ['c', 'a', 'b']);
    });

    test('the profile is read on every call', () async {
      final order = <String>[];
      final pa = ScriptedProvider('a', log: order);
      final pb = ScriptedProvider('b', log: order);
      final ch = chain([pa, pb]);
      await ch.lookup(_query);
      profiles.profile = const UserProfile(providerOrder: [ProviderId('b')]);
      await ch.lookup(_query);
      expect(order, ['a', 'b', 'b', 'a']);
    });

    test('unknown and duplicate ids in the order are ignored', () async {
      profiles.profile = const UserProfile(
        providerOrder: [ProviderId('zz'), ProviderId('b'), ProviderId('b')],
      );
      final order = <String>[];
      final pa = ScriptedProvider('a', log: order);
      final pb = ScriptedProvider('b', log: order);
      await chain([pa, pb]).lookup(_query);
      expect(order, ['b', 'a']);
    });

    test('providers without the mode are skipped, not called', () async {
      final ru = ScriptedProvider(
        'ru',
        modes: {LookupMode.enRu},
        answer: result('ru'),
        log: log,
      );
      final en = ScriptedProvider(
        'en',
        modes: {LookupMode.enEn},
        answer: result('en'),
        log: log,
      );
      final r = _success(await chain([ru, en]).lookup(_query));
      expect(r.result.provider, const ProviderId('en'));
      expect(r.failedBefore, isEmpty);
      expect(log, ['en']);

      log.clear();
      final r2 = _success(
        await chain([ru, en])
            .lookup(const LookupQuery(text: 'run', mode: LookupMode.enRu)),
      );
      expect(r2.result.provider, const ProviderId('ru'));
      expect(log, ['ru']);
    });

    test('no provider supports the mode: empty failure', () async {
      final en = ScriptedProvider('en', modes: {LookupMode.enEn});
      final f = _failure(
        await chain([en])
            .lookup(const LookupQuery(text: 'x', mode: LookupMode.enRu)),
      );
      expect(f.attempts, isEmpty);
      expect(en.calls, isEmpty);
    });
  });

  group('explicit provider', () {
    test('calls only that provider, ignoring profile order', () async {
      profiles.profile = const UserProfile(providerOrder: [ProviderId('a')]);
      final a = ScriptedProvider('a', answer: result('a'), log: log);
      final b = ScriptedProvider('b', answer: result('b'), log: log);
      final r = _success(
        await chain([a, b]).lookup(_query, only: const ProviderId('b')),
      );
      expect(r.result.provider, const ProviderId('b'));
      expect(log, ['b']);
    });

    test('no fallback when it fails', () async {
      final a = ScriptedProvider('a', answer: result('a'), log: log);
      final b = ScriptedProvider(
        'b',
        failure: const ProviderUnavailable(),
        log: log,
      );
      final f = _failure(
        await chain([a, b]).lookup(_query, only: const ProviderId('b')),
      );
      expect(f.attempts, [
        const ProviderAttempt(ProviderId('b'), AttemptFailure.unavailable),
      ]);
      expect(log, ['b']);
    });

    test('empty answer from it is a failure, no fallback', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      final b = ScriptedProvider('b', answer: result('b', const []));
      final f = _failure(
        await chain([a, b]).lookup(_query, only: const ProviderId('b')),
      );
      expect(f.attempts.single.failure, AttemptFailure.empty);
      expect(a.calls, isEmpty);
    });

    test('times out like any provider', () async {
      final b = ScriptedProvider('b', hang: true);
      final f = _failure(
        await chain(
          [b],
          timeout: const Duration(milliseconds: 5),
        ).lookup(_query, only: const ProviderId('b')),
      );
      expect(f.attempts.single.failure, AttemptFailure.timedOut);
    });

    test('unregistered id', () async {
      final f = _failure(
        await chain([]).lookup(_query, only: const ProviderId('nope')),
      );
      expect(f.attempts, [
        const ProviderAttempt(ProviderId('nope'), AttemptFailure.unregistered),
      ]);
    });

    test('provider that does not support the mode is not called', () async {
      final b = ScriptedProvider('b', modes: {LookupMode.enRu});
      final f = _failure(
        await chain([b]).lookup(_query, only: const ProviderId('b')),
      );
      expect(f.attempts.single.failure, AttemptFailure.unsupported);
      expect(b.calls, isEmpty);
    });
  });

  group('cancellation', () {
    test('already cancelled: throws and calls nobody', () async {
      final a = ScriptedProvider('a', answer: result('a'));
      final token = CancelToken()..cancel();
      await expectLater(
        chain([a]).lookup(_query, cancel: token),
        throwsA(isA<CancelledException>()),
      );
      expect(a.calls, isEmpty);
    });

    test('cancelled while a provider runs: no fallback to the next', () async {
      final token = CancelToken();
      final a = ScriptedProvider('a', onCall: token.cancel, log: log);
      final b = ScriptedProvider('b', answer: result('b'), log: log);
      await expectLater(
        chain([a, b]).lookup(_query, cancel: token),
        throwsA(isA<CancelledException>()),
      );
      expect(log, ['a']);
    });

    test('cancelled after a provider answered: throws, no result', () async {
      final token = CancelToken();
      final a = ScriptedProvider(
        'a',
        answer: result('a'),
        // Answers normally; cancel arrives right after the call started.
        onCall: () => Future<void>.microtask(token.cancel),
      );
      await expectLater(
        chain([a]).lookup(_query, cancel: token),
        throwsA(isA<CancelledException>()),
      );
    });

    test('the token is passed to providers', () async {
      final token = CancelToken();
      final a = ScriptedProvider('a', answer: result('a'));
      await chain([a]).lookup(_query, cancel: token);
      expect(a.tokens.single, same(token));
    });
  });
}
