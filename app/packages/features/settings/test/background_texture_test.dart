import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:core_testing/core_testing.dart';
import 'package:features_common/features_common.dart';
import 'package:features_settings/features_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

void main() {
  late Directory temp;
  late String backgrounds;
  late FakeProfileRepository profile;
  String? picked;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('background_texture_');
    backgrounds = '${temp.path}/backgrounds';
    profile = FakeProfileRepository();
    picked = null;
  });

  tearDown(() => temp.deleteSync(recursive: true));

  String makeImage(String name, int size) {
    final file = File('${temp.path}/$name')
      ..writeAsBytesSync(List<int>.filled(size, 7));
    return file.path;
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
          dictionaryLibraryProvider.overrideWithValue(FakeDictionaryLibrary()),
          lookupProvidersProvider.overrideWithValue(const []),
          backgroundsDirectoryProvider.overrideWithValue(backgrounds),
          backgroundFilePickerProvider.overrideWithValue(() async => picked),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // File IO is real, so it runs outside the fake-async zone of the test.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapOwn(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('texture-own')));
    await settle(tester);
  }

  testWidgets('a built-in texture saves BuiltInTexture(id)', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('texture-linen')));
    await tester.pumpAndSettle();
    expect(
      (await profile.get()).display.texture,
      const BuiltInTexture('linen'),
    );
    await tester.tap(find.byKey(const Key('texture-none')));
    await tester.pumpAndSettle();
    expect((await profile.get()).display.texture, const NoTexture());
  });

  testWidgets('"Own…" copies the file and saves FileTexture', (tester) async {
    picked = makeImage('photo.PNG', 100);
    await pump(tester);
    await tapOwn(tester);
    final texture = (await profile.get()).display.texture;
    expect(texture, isA<FileTexture>());
    final path = (texture as FileTexture).path;
    expect(path, startsWith('$backgrounds/'));
    expect(
      RegExp(r'^[0-9a-f]{64}\.png$').hasMatch(path.split('/').last),
      isTrue,
      reason: path,
    );
    expect(File(path).readAsBytesSync(), List<int>.filled(100, 7));
  });

  testWidgets('a file over 5 MB is rejected with a message', (tester) async {
    picked = makeImage('big.jpg', maxBackgroundBytes + 1);
    await pump(tester);
    await tapOwn(tester);
    expect(find.byKey(const Key('texture-error')), findsOneWidget);
    expect((await profile.get()).display.texture, const NoTexture());
    expect(Directory(backgrounds).existsSync(), isFalse);
  });

  testWidgets('replacing the own image deletes the previous file', (
    tester,
  ) async {
    picked = makeImage('a.png', 50);
    await pump(tester);
    await tapOwn(tester);
    final first = ((await profile.get()).display.texture as FileTexture).path;
    expect(File(first).existsSync(), isTrue);

    picked = makeImage('b.jpg', 60);
    await tapOwn(tester);
    final second = ((await profile.get()).display.texture as FileTexture).path;
    expect(second, isNot(first));
    expect(File(second).existsSync(), isTrue);
    expect(File(first).existsSync(), isFalse);
  });

  testWidgets('switching to a built-in texture deletes the own image', (
    tester,
  ) async {
    picked = makeImage('a.png', 50);
    await pump(tester);
    await tapOwn(tester);
    final own = ((await profile.get()).display.texture as FileTexture).path;
    await tester.tap(find.byKey(const Key('texture-paper')));
    await settle(tester);
    expect(File(own).existsSync(), isFalse);
    expect(
      (await profile.get()).display.texture,
      const BuiltInTexture('paper'),
    );
  });

  testWidgets('a cancelled dialog changes nothing', (tester) async {
    await pump(tester);
    await tapOwn(tester);
    expect((await profile.get()).display.texture, const NoTexture());
    expect(find.byKey(const Key('texture-error')), findsNothing);
  });

  testWidgets('the visibility slider saves on release', (tester) async {
    await pump(tester);
    final slider = find.byKey(const Key('texture-opacity'));
    await tester.drag(slider, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect((await profile.get()).display.textureOpacity, 0);
  });

  Container sampleBox(WidgetTester tester, String id) =>
      tester.widget<Container>(
        find.descendant(
          of: find.byKey(Key('texture-$id')),
          matching: find.byType(Container),
        ),
      );

  testWidgets('the selection frame is drawn above the texture', (tester) async {
    profile = FakeProfileRepository(
      const UserProfile(
        display: DisplayPrefs(texture: BuiltInTexture('noise')),
      ),
    );
    await pump(tester);
    final selected = sampleBox(tester, 'noise');
    // The picture is the child; a frame in `decoration` would be covered.
    expect(
      find.descendant(
        of: find.byKey(const Key('texture-noise')),
        matching: find.byType(ColorFiltered),
      ),
      findsOneWidget,
    );
    expect((selected.decoration! as BoxDecoration).border, isNull);
    final frame = selected.foregroundDecoration! as BoxDecoration;
    expect((frame.border! as Border).top.width, 3);
    final other = sampleBox(tester, 'paper');
    final otherFrame = other.foregroundDecoration! as BoxDecoration;
    expect((otherFrame.border! as Border).top.width, 1);
  });

  testWidgets('the paragraph sample is drawn on the chosen texture', (
    tester,
  ) async {
    await pump(tester);
    final sample = find.byKey(const Key('night-sample'));
    expect(
      find.descendant(of: sample, matching: find.byType(ColorFiltered)),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('texture-paper')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sample, matching: find.byType(ColorFiltered)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('day-sample')),
        matching: find.byType(ColorFiltered),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('texture-none')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sample, matching: find.byType(ColorFiltered)),
      findsNothing,
    );
  });

  // `overlay` also paints transparent pixels, so an unclipped filter floods
  // the whole settings list with the sample's background (U-7).
  testWidgets('every texture filter is clipped right above it', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('texture-paper')));
    await tester.pumpAndSettle();
    final filters = find.byType(ColorFiltered);
    expect(filters, findsWidgets);
    for (final element in filters.evaluate()) {
      Widget? parent;
      element.visitAncestorElements((e) {
        parent = e.widget;
        return false;
      });
      expect(parent, isA<ClipRect>());
    }
  });

  testWidgets('choosing a texture is logged at info level', (tester) async {
    final records = <LogRecord>[];
    final previous = Logger.root.level;
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(() async {
      await subscription.cancel();
      Logger.root.level = previous;
    });
    await pump(tester);
    await tester.tap(find.byKey(const Key('texture-linen')));
    await tester.pumpAndSettle();
    final info = records.where((r) => r.level == Level.INFO);
    expect(info.map((r) => r.message), contains('Texture chosen: linen'));
  });
}
