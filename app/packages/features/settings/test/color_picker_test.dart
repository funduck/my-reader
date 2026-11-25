import 'package:features_settings/features_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('wheel geometry', () {
    const size = Size(200, 200);

    test('the centre is white, the right rim is red', () {
      final centre = wheelHueSaturation(const Offset(100, 100), size);
      expect(centre.saturation, 0);
      final right = wheelHueSaturation(const Offset(200, 100), size);
      expect(right.hue, closeTo(0, 1e-9));
      expect(right.saturation, 1);
    });

    test('the hue grows clockwise, outside the rim is clamped', () {
      final bottom = wheelHueSaturation(const Offset(100, 300), size);
      expect(bottom.hue, closeTo(90, 1e-9));
      expect(bottom.saturation, 1);
      final left = wheelHueSaturation(const Offset(50, 100), size);
      expect(left.hue, closeTo(180, 1e-9));
      expect(left.saturation, closeTo(0.5, 1e-9));
    });

    test('wheelOffset is the inverse', () {
      for (final (h, s) in [(0.0, 1.0), (123.0, 0.4), (300.0, 0.8)]) {
        final hs = wheelHueSaturation(wheelOffset(h, s, size), size);
        expect(hs.hue, closeTo(h, 1e-6));
        expect(hs.saturation, closeTo(s, 1e-6));
      }
    });
  });

  group('dialog', () {
    Future<List<int?>> open(WidgetTester tester, int initial) async {
      final results = <int?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showColorPicker(context, title: 'Pick', initial: initial),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('HEX input is returned by Select', (tester) async {
      final results = await open(tester, 0xFF000000);
      expect(find.text('000000'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('color-hex')), 'F4ECD8');
      await tester.pump();
      await tester.tap(find.byKey(const Key('color-select')));
      await tester.pumpAndSettle();
      expect(results, [0xFFF4ECD8]);
    });

    testWidgets('an invalid HEX disables Select', (tester) async {
      await open(tester, 0xFFFFFFFF);
      await tester.enterText(find.byKey(const Key('color-hex')), 'ZZ');
      await tester.pump();
      expect(find.text('Six hex digits'), findsOneWidget);
      final select = tester.widget<FilledButton>(
        find.byKey(const Key('color-select')),
      );
      expect(select.onPressed, isNull);
    });

    testWidgets('a tap on the wheel picks the hue and updates HEX', (
      tester,
    ) async {
      final results = await open(tester, 0xFFFFFFFF);
      final wheel = find.byKey(const Key('color-wheel'));
      final rect = tester.getRect(wheel);
      // Just inside the right rim at full brightness: almost pure red.
      await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
      await tester.pump();
      final hex = tester
          .widget<TextField>(find.byKey(const Key('color-hex')))
          .controller!
          .text;
      await tester.tap(find.byKey(const Key('color-select')));
      await tester.pumpAndSettle();
      final picked = results.single!;
      expect(hex, formatHexColor(picked));
      expect((picked >> 16) & 0xFF, 0xFF);
      expect((picked >> 8) & 0xFF, lessThan(8));
      expect(picked & 0xFF, lessThan(8));
    });

    testWidgets('the hue survives brightness at zero', (tester) async {
      await open(tester, 0xFF0000FF);
      final slider = find.byKey(const Key('color-brightness'));
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.left, rect.center.dy));
      await tester.pump();
      expect(find.text('000000'), findsOneWidget);
      await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
      await tester.pump();
      expect(find.text('0000FF'), findsOneWidget);
    });

    testWidgets('Cancel returns null', (tester) async {
      final results = await open(tester, 0xFF123456);
      await tester.tap(find.byKey(const Key('color-cancel')));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });
  });
}
