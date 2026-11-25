import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:test/test.dart';

/// Behaviour every [ProfileRepository] must have.
///
/// [create] returns a fresh repository with nothing saved for each test.
void profileRepositoryContract(FutureOr<ProfileRepository> Function() create) {
  group('ProfileRepository contract', () {
    late ProfileRepository repo;

    setUp(() async => repo = await create());

    test('get returns the default profile if nothing was saved', () async {
      expect(await repo.get(), const UserProfile());
    });

    test('save then get returns an equal profile', () async {
      const profile = UserProfile(
        mode: LookupMode.enRu,
        level: CefrLevel.c1,
        providerOrder: [ProviderId('b'), ProviderId('a')],
        serviceUrl: 'http://192.168.1.2:8080',
      );
      await repo.save(profile);
      expect(await repo.get(), profile);
    });

    test('saving again replaces the profile', () async {
      await repo.save(const UserProfile(level: CefrLevel.c1));
      await repo.save(const UserProfile(level: CefrLevel.a2));
      expect((await repo.get()).level, CefrLevel.a2);
    });

    test('update changes only what it changes', () async {
      await repo.save(const UserProfile(level: CefrLevel.c1));
      final saved = await repo.update((p) => p.copyWith(mode: LookupMode.enRu));
      expect(
        saved,
        const UserProfile(level: CefrLevel.c1, mode: LookupMode.enRu),
      );
      expect(await repo.get(), saved);
    });

    test('concurrent updates lose nothing', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++)
          repo.update(
            (p) => p.copyWith(
              providerOrder: [...p.providerOrder, ProviderId('p$i')],
            ),
          ),
      ]);
      expect((await repo.get()).providerOrder.map((id) => id.value).toSet(), {
        for (var i = 0; i < 20; i++) 'p$i',
      });
    });

    test('watch emits the current profile first, then every save', () async {
      final emitted = <UserProfile>[];
      final sub = repo.watch().listen(emitted.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emitted, [const UserProfile()]);

      const changed = UserProfile(mode: LookupMode.enRu);
      await repo.save(changed);
      await pumpEventQueue();
      expect(emitted, [const UserProfile(), changed]);
    });
  });
}
