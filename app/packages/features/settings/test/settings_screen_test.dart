import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_settings/features_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// Store whose downloads wait for the test.
class _SlowPackStore extends FakePackStore {
  new({super.offered});

  final Completer<void> gate = Completer<void>();

  @override
  Future<InstalledPack> download(String id, PackProgress onProgress) {
    onProgress(0.25);
    return gate.future.then((_) => super.download(id, onProgress));
  }
}

const _enEn = PackManifestEntry(
  id: 'en-en',
  version: '2',
  sizeBytes: 50 * 1024 * 1024,
  sha256: 'a',
);
const _levels = PackManifestEntry(
  id: 'en-levels',
  version: '1',
  sizeBytes: 1024 * 1024,
  sha256: 'b',
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FakeProfileRepository profile,
    required PackStore packs,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(profile),
          packStoreProvider.overrideWithValue(packs),
          dictionaryLibraryProvider.overrideWithValue(FakeDictionaryLibrary()),
          lookupProvidersProvider.overrideWithValue(const []),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('profile settings', () {
    testWidgets('shows the stored values and the default address hint', (
      tester,
    ) async {
      final profile = FakeProfileRepository(
        const UserProfile(
          mode: LookupMode.enRu,
          level: CefrLevel.c1,
          scope: CheatSheetChapter(),
          serviceUrl: 'http://example.test:9000',
        ),
      );
      await pump(tester, profile: profile, packs: FakePackStore());

      expect(find.text('http://example.test:9000'), findsOneWidget);
      expect(find.text('C1'), findsOneWidget);
      final mode = tester.widget<SegmentedButton<LookupMode>>(
        find.byType(SegmentedButton<LookupMode>),
      );
      expect(mode.selected, {LookupMode.enRu});
      final scope = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      expect(scope.selected, {false});
      expect(find.byKey(const Key('pages')), findsNothing);
    });

    testWidgets('empty address shows the default as a hint', (tester) async {
      await pump(
        tester,
        profile: FakeProfileRepository(),
        packs: FakePackStore(),
      );
      expect(find.text('http://localhost:8080'), findsOneWidget);
    });

    testWidgets('saves the lookup mode', (tester) async {
      final profile = FakeProfileRepository();
      await pump(tester, profile: profile, packs: FakePackStore());

      await tester.tap(find.text('EN → RU'));
      await tester.pumpAndSettle();

      expect((await profile.get()).mode, LookupMode.enRu);
    });

    testWidgets('saves the level', (tester) async {
      final profile = FakeProfileRepository();
      await pump(tester, profile: profile, packs: FakePackStore());

      await tester.tap(find.byKey(const Key('level')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('C2').last);
      await tester.pumpAndSettle();

      expect((await profile.get()).level, CefrLevel.c2);
    });

    testWidgets('saves the number of pages', (tester) async {
      final profile = FakeProfileRepository();
      await pump(tester, profile: profile, packs: FakePackStore());

      await tester.tap(find.byKey(const Key('pages')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.pumpAndSettle();

      expect((await profile.get()).scope, const CheatSheetPages(20));
    });

    testWidgets('switches the piece to the end of the chapter and back', (
      tester,
    ) async {
      final profile = FakeProfileRepository();
      await pump(tester, profile: profile, packs: FakePackStore());

      await tester.tap(find.text('To end of chapter'));
      await tester.pumpAndSettle();
      expect((await profile.get()).scope, const CheatSheetChapter());
      expect(find.byKey(const Key('pages')), findsNothing);

      await tester.tap(find.text('Pages'));
      await tester.pumpAndSettle();
      expect((await profile.get()).scope, CheatSheetScope.defaultScope);
      expect(find.byKey(const Key('pages')), findsOneWidget);
    });
  });

  group('service address', () {
    testWidgets('saves a valid address', (tester) async {
      final profile = FakeProfileRepository();
      await pump(tester, profile: profile, packs: FakePackStore());

      await tester.enterText(
        find.byType(TextField),
        '  http://192.168.1.5:8080 ',
      );
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();

      expect((await profile.get()).serviceUrl, 'http://192.168.1.5:8080');
    });

    testWidgets('rejects an invalid address and keeps the old one', (
      tester,
    ) async {
      final profile = FakeProfileRepository(
        const UserProfile(serviceUrl: 'http://old.test'),
      );
      await pump(tester, profile: profile, packs: FakePackStore());

      await tester.enterText(find.byType(TextField), 'not a url');
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an http:// or https:// address'), findsOneWidget);
      expect((await profile.get()).serviceUrl, 'http://old.test');
    });

    testWidgets('an empty address resets to the default', (tester) async {
      final profile = FakeProfileRepository(
        const UserProfile(serviceUrl: 'http://old.test'),
      );
      await pump(tester, profile: profile, packs: FakePackStore());

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();

      expect((await profile.get()).serviceUrl, isNull);
    });

    test('isValidServiceUrl', () {
      expect(isValidServiceUrl('http://localhost:8080'), isTrue);
      expect(isValidServiceUrl('https://example.org/api'), isTrue);
      expect(isValidServiceUrl('ftp://example.org'), isFalse);
      expect(isValidServiceUrl('localhost:8080'), isFalse);
      expect(isValidServiceUrl('http://'), isFalse);
    });
  });

  group('packs', () {
    testWidgets('lists the manifest with sizes and statuses', (tester) async {
      final packs = FakePackStore(
        offered: [_enEn, _levels],
        installedPacks: [const InstalledPack(id: 'en-en', version: '1')],
      );
      await pump(tester, profile: FakeProfileRepository(), packs: packs);

      expect(find.text('en-en'), findsOneWidget);
      expect(find.text('Installed 1, update 2 · 50.0 MB'), findsOneWidget);
      expect(find.text('Not installed · 1.0 MB'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('downloads a pack with progress', (tester) async {
      final packs = _SlowPackStore(offered: [_levels]);
      await pump(tester, profile: FakeProfileRepository(), packs: packs);

      await tester.tap(find.text('Download'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Downloading 25% · 1.0 MB'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      packs.gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Installed 1 · 1.0 MB'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(await packs.installed(), [
        const InstalledPack(id: 'en-levels', version: '1'),
      ]);
    });

    testWidgets('shows a failed download and allows a retry', (tester) async {
      final packs = FakePackStore(offered: [_levels]);
      await pump(tester, profile: FakeProfileRepository(), packs: packs);

      // The manifest was read; now the network drops during the download.
      packs.error = Exception('boom');
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Download failed'), findsOneWidget);
      expect(find.text('Not installed · 1.0 MB'), findsOneWidget);

      packs.error = null;
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Download failed'), findsNothing);
      expect(find.text('Installed 1 · 1.0 MB'), findsOneWidget);
    });

    testWidgets('offline: installed packs stay visible, manifest error shown', (
      tester,
    ) async {
      final packs = FakePackStore(
        offered: [_enEn],
        installedPacks: [const InstalledPack(id: 'en-en', version: '1')],
      )..error = Exception('no network');
      await pump(tester, profile: FakeProfileRepository(), packs: packs);

      expect(find.textContaining('Service is not reachable'), findsOneWidget);
      expect(find.text('Installed 1'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
      expect(find.text('Update'), findsNothing);
    });

    testWidgets('refresh picks up a new manifest', (tester) async {
      final packs = FakePackStore()..error = Exception('no network');
      await pump(tester, profile: FakeProfileRepository(), packs: packs);
      expect(find.textContaining('Service is not reachable'), findsOneWidget);

      packs
        ..error = null
        ..offered.add(_levels);
      await tester.tap(find.byTooltip('Refresh packs'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Service is not reachable'), findsNothing);
      expect(find.text('Not installed · 1.0 MB'), findsOneWidget);
    });
  });
}
