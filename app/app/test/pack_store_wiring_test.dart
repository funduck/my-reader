import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_reader_app/bootstrap.dart';

void main() {
  late FakeProfileRepository profile;
  late ProviderContainer container;

  setUp(() {
    profile = FakeProfileRepository();
    container = ProviderContainer(
      overrides: [
        ...buildOverrides(),
        profileRepositoryProvider.overrideWithValue(profile),
      ],
    );
    addTearDown(container.dispose);
  });

  LazyHttpPackStore store() =>
      container.read(packStoreProvider) as LazyHttpPackStore;

  test('the default service address is http://localhost:8080', () async {
    container.listen(serviceUrlProvider, (_, _) {});
    await container.read(serviceUrlProvider.future);
    expect(store().baseUri, Uri.parse('http://localhost:8080'));
  });

  test('a new service address in the profile recreates the store', () async {
    container.listen(serviceUrlProvider, (_, _) {});
    await container.read(serviceUrlProvider.future);
    final before = store();

    await profile.save(const UserProfile(serviceUrl: 'http://10.0.0.2:9000'));
    await container.pump();

    expect(store(), isNot(same(before)));
    expect(store().baseUri, Uri.parse('http://10.0.0.2:9000'));
  });

  test('clearing the address returns to the default', () async {
    await profile.save(const UserProfile(serviceUrl: 'http://10.0.0.2:9000'));
    container.listen(serviceUrlProvider, (_, _) {});
    await container.read(serviceUrlProvider.future);
    expect(store().baseUri.host, '10.0.0.2');

    await profile.save(const UserProfile());
    await container.pump();

    expect(store().baseUri, Uri.parse('http://localhost:8080'));
  });

  test('LazyHttpPackStore creates its directory on first use', () async {
    final tmp = await Directory.systemTemp.createTemp('packs_test');
    addTearDown(() => tmp.delete(recursive: true));
    final dir = Directory('${tmp.path}/nested/packs');
    final lazy = LazyHttpPackStore(
      baseUri: Uri.parse('http://localhost:8080'),
      directory: () async => dir,
    );
    addTearDown(lazy.close);

    expect(dir.existsSync(), isFalse);
    expect(await lazy.installed(), isEmpty);
    expect(await lazy.pathOf('en-en'), isNull);
    expect(dir.existsSync(), isTrue);
  });
}
