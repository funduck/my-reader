import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_reader_app/app.dart';

void main() {
  Future<ThemeMode> themeMode(
    WidgetTester tester,
    FakeProfileRepository profile,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(profile)],
        child: const MyReaderApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    return tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;
  }

  testWidgets('night mode of the profile gives the dark theme', (tester) async {
    final profile = FakeProfileRepository(
      const UserProfile(display: DisplayPrefs(mode: DisplayMode.night)),
    );
    expect(await themeMode(tester, profile), ThemeMode.dark);
    await profile.save(const UserProfile());
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
  });
}
