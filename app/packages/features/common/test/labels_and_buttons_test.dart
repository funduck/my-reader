import 'dart:ui' show Tristate;

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('InfoLabel', () {
    testWidgets('is text on a fill: no border, no tap, no focus', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const InfoLabel(key: Key('label'), child: Text('B2'))),
      );

      expect(find.text('B2'), findsOneWidget);
      final root = find.byKey(const Key('label'));
      for (final type in [
        InkWell,
        GestureDetector,
        Focus,
        ButtonStyleButton,
        Chip,
      ]) {
        expect(
          find.descendant(of: root, matching: find.byType(type)),
          findsNothing,
          reason: '$type',
        );
      }
      final decoration = tester.widget<DecoratedBox>(
        find.descendant(of: root, matching: find.byType(DecoratedBox)),
      );
      final box = decoration.decoration as BoxDecoration;
      expect(box.border, isNull);
      expect(box.color, isNotNull);
    });

    testWidgets('is not a button for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const InfoLabel(
            key: Key('label'),
            semanticsLabel: 'Level B2',
            child: Text('B2'),
          ),
        ),
      );

      final node = tester.getSemantics(find.byKey(const Key('label')));
      expect(node.label, 'Level B2');
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isFalse);
      expect(data.flagsCollection.isFocused, Tristate.none);
      expect(data.flagsCollection.isToggled, Tristate.none);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });

    testWidgets('reads its own text without a semantics label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const InfoLabel(key: Key('label'), child: Text('B2'))),
      );

      final node = tester.getSemantics(find.bySemanticsLabel('B2'));
      expect(node.getSemanticsData().flagsCollection.isButton, isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });

  group('LevelBadge', () {
    testWidgets('is the common label', (tester) async {
      await tester.pumpWidget(
        _app(const LevelBadge(level: WordLevel(CefrLevel.c1))),
      );

      expect(find.widgetWithText(InfoLabel, 'C1'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(Chip), findsNothing);
    });

    testWidgets('marks an estimate with ≈ and says so aloud', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const LevelBadge(level: WordLevel(CefrLevel.b2, estimated: true))),
      );

      expect(find.text('≈B2'), findsOneWidget);
      expect(find.bySemanticsLabel('Level about B2'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('draws nothing for an unknown level', (tester) async {
      await tester.pumpWidget(
        _app(const LevelBadge(level: WordLevel(CefrLevel.unknown))),
      );

      expect(find.byType(InfoLabel), findsNothing);
    });
  });

  group('ToggleButton', () {
    Widget toggle({required bool selected, ValueChanged<bool>? onChanged}) =>
        _app(
          ToggleButton(
            key: const Key('toggle'),
            label: 'Знаю',
            selected: selected,
            onChanged: onChanged,
          ),
        );

    testWidgets('is a pressable button and reports the new state', (
      tester,
    ) async {
      final changes = <bool>[];
      await tester.pumpWidget(toggle(selected: false, onChanged: changes.add));

      expect(find.byType(OutlinedButton), findsOneWidget);
      await tester.tap(find.byKey(const Key('toggle')));
      await tester.pumpWidget(toggle(selected: true, onChanged: changes.add));
      await tester.tap(find.byKey(const Key('toggle')));

      expect(changes, [true, false]);
    });

    testWidgets('shows the state in an icon, not only in colour', (
      tester,
    ) async {
      await tester.pumpWidget(toggle(selected: false, onChanged: (_) {}));
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);

      await tester.pumpWidget(toggle(selected: true, onChanged: (_) {}));
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Знаю'), findsOneWidget);
    });

    testWidgets('is a button with a toggled state for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(toggle(selected: false, onChanged: (_) {}));
      var data = tester
          .getSemantics(find.byKey(const Key('toggle')))
          .getSemanticsData();
      expect(data.label, 'Знаю');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isToggled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      await tester.pumpWidget(toggle(selected: true, onChanged: (_) {}));
      data = tester
          .getSemantics(find.byKey(const Key('toggle')))
          .getSemanticsData();
      expect(data.flagsCollection.isToggled, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('does not react when disabled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(toggle(selected: false));

      final data = tester
          .getSemantics(find.byKey(const Key('toggle')))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      handle.dispose();
    });
  });
}
