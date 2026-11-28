import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:reader_simple/src/highlight_plates.dart';

/// The plates behind the text of [selectable] (a finder of one
/// `SelectableText`), in the order of the text.
List<Plate> platesOf(WidgetTester tester, Finder selectable) {
  final plates = find.ancestor(
    of: selectable,
    matching: find.byType(HighlightPlates),
  );
  return tester.renderObject<RenderHighlightPlates>(plates.first).plates;
}

/// What is marked in [selectable]: the text of every marked range and its
/// colour. A range that runs over several lines is one mark.
List<(String, Color)> marksOf(WidgetTester tester, Finder selectable) {
  final text = tester
      .widget<SelectableText>(selectable)
      .textSpan!
      .toPlainText();
  final result = <(String, Color)>[];
  int? lastStart;
  for (final plate in platesOf(tester, selectable)) {
    if (lastStart == plate.start) continue;
    lastStart = plate.start;
    result.add((text.substring(plate.start, plate.end), plate.color));
  }
  return result;
}

/// [marksOf] for every `SelectableText` on screen, one after another.
List<(String, Color)> allMarks(WidgetTester tester) => [
  for (var i = 0; i < find.byType(SelectableText).evaluate().length; i++)
    ...marksOf(tester, find.byType(SelectableText).at(i)),
];
