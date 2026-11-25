import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_settings/features_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

void main() {
  Future<void> pump(WidgetTester tester, FakeProfileRepository profile) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(profile),
          packStoreProvider.overrideWithValue(FakePackStore()),
          dictionaryLibraryProvider.overrideWithValue(FakeDictionaryLibrary()),
          lookupProvidersProvider.overrideWithValue(const []),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  SwitchListTile tile(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(Key(key)));

  testWidgets('"Highlights" follows "Reading"', (tester) async {
    await pump(tester, FakeProfileRepository());
    final reading = tester.getTopLeft(find.text('Reading')).dy;
    final highlights = tester.getTopLeft(find.text('Highlights')).dy;
    final address = tester.getTopLeft(find.text('Service address')).dy;
    expect(highlights, greaterThan(reading));
    expect(highlights, lessThan(address));
  });

  testWidgets('the switches show the profile and save a change', (
    tester,
  ) async {
    final profile = FakeProfileRepository();
    await pump(tester, profile);
    expect(tile(tester, 'highlights-enabled').value, isTrue);
    expect(tile(tester, 'highlight-difficult').value, isFalse);
    expect(tile(tester, 'highlight-cheat-sheet').value, isTrue);
    await tester.tap(find.byKey(const Key('highlight-difficult')));
    await tester.pumpAndSettle();
    expect((await profile.get()).highlights.difficult, isTrue);
    expect(tile(tester, 'highlight-difficult').value, isTrue);
    await tester.tap(find.byKey(const Key('highlight-looked-up')));
    await tester.pumpAndSettle();
    final saved = (await profile.get()).highlights;
    expect(saved.lookedUp, isFalse);
    expect(saved.difficult, isTrue);
  });

  testWidgets('a switched off master makes the kinds inactive', (tester) async {
    final profile = FakeProfileRepository();
    await pump(tester, profile);
    await tester.tap(find.byKey(const Key('highlights-enabled')));
    await tester.pumpAndSettle();
    expect((await profile.get()).highlights.enabled, isFalse);
    for (final key in [
      'highlight-difficult',
      'highlight-cheat-sheet',
      'highlight-looked-up',
      'highlight-recent',
    ]) {
      expect(tile(tester, key).onChanged, isNull, reason: key);
    }
    expect(tile(tester, 'highlights-enabled').onChanged, isNotNull);
  });

  testWidgets('a tap on a bar saves the threshold', (tester) async {
    final profile = FakeProfileRepository();
    await pump(tester, profile);
    expect((await profile.get()).highlights.minFrequencyBars, 1);
    await tester.tap(find.byKey(const Key('frequency-bar-4')));
    await tester.pumpAndSettle();
    var saved = (await profile.get()).highlights;
    expect(saved.minFrequencyBars, 4);
    // The other fields stay as they were.
    expect(saved.cheatSheet, isTrue);
    expect(saved.difficult, isFalse);
    expect(
      tester.widget<FrequencyThreshold>(find.byType(FrequencyThreshold)).bars,
      4,
    );
    await tester.tap(find.byKey(const Key('frequency-bar-1')));
    await tester.pumpAndSettle();
    saved = (await profile.get()).highlights;
    expect(saved.minFrequencyBars, 1);
  });

  testWidgets('the threshold is read from the profile', (tester) async {
    final profile = FakeProfileRepository(
      const UserProfile(highlights: HighlightPrefs(minFrequencyBars: 3)),
    );
    await pump(tester, profile);
    expect(
      tester.widget<FrequencyThreshold>(find.byType(FrequencyThreshold)).bars,
      3,
    );
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const Key('frequency-bar-3'))),
      matchesSemantics(
        label: 'at least 3 of 5 bars',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
