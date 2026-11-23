import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_settings/features_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'font_fixture.dart';

void main() {
  late Directory temp;
  late String fonts;
  late FakeProfileRepository profile;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('font_choice_');
    fonts = '${temp.path}/app/fonts';
    profile = FakeProfileRepository();
  });

  tearDown(() {
    // A test may leave an unreadable folder behind.
    Process.runSync('chmod', ['-R', '755', temp.path]);
    temp.deleteSync(recursive: true);
  });

  String makeFont(
    String relative,
    String family,
    String style, {
    int version = 0x00010000,
  }) {
    final file = File('${temp.path}/src/$relative')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        buildTestFont([(3, 1, family), (3, 2, style)], version: version),
      );
    return file.path;
  }

  group('findFonts', () {
    test(
      'finds ttf and otf in subfolders, skips ttc and other files',
      () async {
        makeFont('b.ttf', 'Lora', 'Regular');
        makeFont('deep/er/a.OTF', 'Alegreya', 'Bold', version: 0x4F54544F);
        makeFont('c.ttc', 'Collection', 'Regular');
        File('${temp.path}/src/notes.txt').writeAsStringSync('hi');
        final found = await findFonts('${temp.path}/src');
        expect(found.map((e) => e.name), ['Alegreya Bold', 'Lora Regular']);
        expect(found.every((e) => File(e.path).existsSync()), isTrue);
      },
    );

    test('drops duplicate names and names a broken file by its file', () async {
      makeFont('one/x.ttf', 'Lora', 'Regular');
      makeFont('two/y.ttf', 'Lora', 'Regular');
      File('${temp.path}/src/broken.ttf')
        ..createSync(recursive: true)
        ..writeAsStringSync('nope');
      final found = await findFonts('${temp.path}/src');
      expect(found.map((e) => e.name), ['broken.ttf', 'Lora Regular']);
    });

    test('an unreadable folder gives an empty list', () async {
      expect(await findFonts('${temp.path}/missing'), isEmpty);
      makeFont('locked/a.ttf', 'Lora', 'Regular');
      Process.runSync('chmod', ['000', '${temp.path}/src/locked']);
      expect(await findFonts('${temp.path}/src'), isEmpty);
    });
  });

  group('importFont', () {
    test('copies by sha256 into the fonts directory', () async {
      final path = makeFont('a.ttf', 'Lora', 'Regular');
      final copy = await importFont(path, fonts);
      expect(copy, matches(RegExp(r'/fonts/[0-9a-f]{64}\.ttf$')));
      expect(File(copy!).readAsBytesSync(), File(path).readAsBytesSync());
      expect(await importFont('${temp.path}/none.ttf', fonts), isNull);
    });
  });

  group('settings', () {
    String? pickedFolder;
    var pickedFiles = const <String>[];
    var byFiles = false;

    setUp(() {
      pickedFolder = null;
      pickedFiles = const [];
      byFiles = false;
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
    }

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileRepositoryProvider.overrideWithValue(profile),
            packStoreProvider.overrideWithValue(FakePackStore()),
            dictionaryLibraryProvider.overrideWithValue(
              FakeDictionaryLibrary(),
            ),
            lookupProvidersProvider.overrideWithValue(const []),
            fontsDirectoryProvider.overrideWithValue(fonts),
            fontPickByFilesProvider.overrideWithValue(byFiles),
            fontFolderPickerProvider.overrideWithValue(
              () async => pickedFolder,
            ),
            fontFilesPickerProvider.overrideWithValue(() async => pickedFiles),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await settle(tester);
    }

    Future<void> select(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const Key('font-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await settle(tester);
    }

    List<File> copies() => Directory(fonts).existsSync()
        ? Directory(fonts).listSync().whereType<File>().toList()
        : [];

    testWidgets('choosing a font copies the file and saves font; '
        '"Системный" deletes the copy and saves null', (tester) async {
      makeFont('a.ttf', 'Lora', 'Regular');
      makeFont('b.ttf', 'Alegreya', 'Bold');
      pickedFolder = '${temp.path}/src';
      await pump(tester);
      await tester.tap(find.byKey(const Key('font-pick')));
      await settle(tester);
      expect((await profile.get()).display.fontFolder, pickedFolder);

      await select(tester, 'Lora Regular');
      final first = (await profile.get()).display.font!;
      expect(first.family, 'Lora Regular');
      expect(first.path.startsWith('$fonts/'), isTrue);
      expect(File(first.path).existsSync(), isTrue);
      expect(copies(), hasLength(1));

      await select(tester, 'Alegreya Bold');
      final second = (await profile.get()).display.font!;
      expect(second.family, 'Alegreya Bold');
      expect(File(first.path).existsSync(), isFalse);
      expect(copies().map((f) => f.path), [second.path]);

      await select(tester, 'Системный');
      expect((await profile.get()).display.font, isNull);
      expect(copies(), isEmpty);
    });

    testWidgets('the list is built from the saved folder', (tester) async {
      makeFont('a.ttf', 'Lora', 'Regular');
      profile = FakeProfileRepository(
        UserProfile(display: DisplayPrefs(fontFolder: '${temp.path}/src')),
      );
      await pump(tester);
      await tester.tap(find.byKey(const Key('font-select')));
      await tester.pumpAndSettle();
      expect(find.text('Lora Regular'), findsOneWidget);
      expect(find.text('Системный'), findsWidgets);
    });

    testWidgets('an unreadable saved folder gives a hint and no fonts', (
      tester,
    ) async {
      profile = FakeProfileRepository(
        UserProfile(display: DisplayPrefs(fontFolder: '${temp.path}/missing')),
      );
      await pump(tester);
      expect(find.byKey(const Key('font-folder-hint')), findsOneWidget);
      expect(find.text('Выбери папку ещё раз'), findsOneWidget);
    });

    testWidgets('on Android fonts come from chosen files', (tester) async {
      byFiles = true;
      pickedFiles = [
        makeFont('a.ttf', 'Lora', 'Regular'),
        makeFont('b.ttc', 'Skipped', 'Regular'),
      ];
      await pump(tester);
      expect(find.text('Файлы шрифтов…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('font-pick')));
      await settle(tester);
      await select(tester, 'Lora Regular');
      expect((await profile.get()).display.font?.family, 'Lora Regular');
      expect((await profile.get()).display.fontFolder, isNull);
    });
  });
}
