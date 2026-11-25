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

  testWidgets('"Reading" is the first section', (tester) async {
    await pump(tester, FakeProfileRepository());
    final reading = tester.getTopLeft(find.text('Reading')).dy;
    final address = tester.getTopLeft(find.text('Service address')).dy;
    expect(reading, lessThan(address));
  });

  testWidgets('a preset saves the day and the night palette', (tester) async {
    final profile = FakeProfileRepository();
    await pump(tester, profile);
    await tester.tap(find.byKey(const Key('day-preset-2')));
    await tester.pumpAndSettle();
    var display = (await profile.get()).display;
    expect(display.day.background, 0xFFF4ECD8);
    expect(display.day.text, 0xFF3B2F2F);
    await tester.tap(find.byKey(const Key('night-preset-3')));
    await tester.pumpAndSettle();
    display = (await profile.get()).display;
    expect(display.night.background, 0xFF2B2419);
    expect(display.night.text, 0xFFC8B89A);
    // The field shows the new colour.
    expect(find.text('F4ECD8'), findsOneWidget);
  });

  testWidgets('HEX input saves a valid colour', (tester) async {
    final profile = FakeProfileRepository();
    await pump(tester, profile);
    await tester.enterText(
      find.byKey(const Key('night-background')),
      '#101820',
    );
    await tester.pumpAndSettle();
    expect((await profile.get()).display.night.background, 0xFF101820);
    await tester.enterText(find.byKey(const Key('day-text')), '3b2f2f');
    await tester.pumpAndSettle();
    expect((await profile.get()).display.day.text, 0xFF3B2F2F);
  });

  testWidgets('the colour wheel saves the chosen colour', (tester) async {
    final profile = FakeProfileRepository();
    await pump(tester, profile);
    await tester.tap(find.byKey(const Key('day-background-pick')));
    await tester.pumpAndSettle();
    expect(find.byType(ColorPickerDialog), findsOneWidget);
    await tester.enterText(find.byKey(const Key('color-hex')), 'E6F0E6');
    await tester.pump();
    await tester.tap(find.byKey(const Key('color-select')));
    await tester.pumpAndSettle();
    expect((await profile.get()).display.day.background, 0xFFE6F0E6);
    // The HEX field next to the chip shows it too.
    expect(find.text('E6F0E6'), findsOneWidget);
  });

  testWidgets('an invalid HEX is not saved and shows an error', (tester) async {
    final profile = FakeProfileRepository();
    await pump(tester, profile);
    await tester.enterText(find.byKey(const Key('day-background')), 'ZZZ');
    await tester.pumpAndSettle();
    expect(find.text('Six hex digits, for example F4ECD8'), findsOneWidget);
    expect(
      (await profile.get()).display.day.background,
      DisplayPrefs.defaultDay.background,
    );
  });

  testWidgets('a low contrast is warned about, presets are not', (
    tester,
  ) async {
    final profile = FakeProfileRepository();
    await pump(tester, profile);
    expect(find.textContaining('Low contrast'), findsNothing);
    for (var i = 0; i < dayPresets.length; i++) {
      await tester.tap(find.byKey(Key('day-preset-$i')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('night-preset-$i')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Low contrast'), findsNothing, reason: '$i');
    }
    await tester.enterText(find.byKey(const Key('day-background')), '888888');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('day-text')), '777777');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day-contrast-warning')), findsOneWidget);
    expect(find.byKey(const Key('night-contrast-warning')), findsNothing);
  });

  testWidgets('the mode, font size and sliders are saved', (tester) async {
    final profile = FakeProfileRepository();
    await pump(tester, profile);
    await tester.tap(find.text('Ночь'));
    await tester.pumpAndSettle();
    expect((await profile.get()).display.mode, DisplayMode.night);
    await tester.tap(find.text('A+'));
    await tester.pumpAndSettle();
    expect((await profile.get()).display.fontSize, 19);
    await tester.tap(find.text('A−'));
    await tester.tap(find.text('A−'));
    await tester.pumpAndSettle();
    expect((await profile.get()).display.fontSize, 17);
    final rect = tester.getRect(find.byKey(const Key('dim')));
    await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
    await tester.pumpAndSettle();
    expect((await profile.get()).display.dim, greaterThan(0.7));
  });

  test('contrast follows WCAG', () {
    expect(contrastRatio(0xFF000000, 0xFFFFFFFF), closeTo(21, 0.01));
    expect(contrastRatio(0xFF777777, 0xFF888888), lessThan(minContrast));
    for (final (text, bg) in [...dayPresets, ...nightPresets]) {
      expect(contrastRatio(text, bg), greaterThanOrEqualTo(minContrast));
    }
    expect(parseHexColor('12345'), isNull);
    expect(parseHexColor('#ABCDEF'), 0xFFABCDEF);
  });
}
