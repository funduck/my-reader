import 'dart:convert';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:test/test.dart';

CheatSheetSnapshot _snapshot({
  String book = 'b1',
  List<String> lemmas = const ['spice', 'flow'],
}) => CheatSheetSnapshot(
  book: BookId(book),
  shownAt: DateTime.utc(2024, 5, 6, 7, 8, 9, 10, 11),
  lemmas: lemmas,
);

void main() {
  group('CheatSheetSnapshot', () {
    test('JSON round-trips, the time stays UTC', () {
      final s = _snapshot();
      final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>;
      final back = CheatSheetSnapshot.fromJson(json);
      expect(back, s);
      expect(back.shownAt.isUtc, isTrue);
      expect(back.lemmas, ['spice', 'flow']);
    });

    test('an empty list round-trips', () {
      final s = _snapshot(lemmas: const []);
      final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>;
      expect(CheatSheetSnapshot.fromJson(json), s);
    });

    test('equality and hashCode cover all fields, the order counts', () {
      expect(_snapshot(), _snapshot());
      expect(_snapshot().hashCode, _snapshot().hashCode);
      expect(_snapshot(), isNot(_snapshot(book: 'b2')));
      expect(_snapshot(), isNot(_snapshot(lemmas: const ['flow', 'spice'])));
      expect(_snapshot(), isNot(_snapshot(lemmas: const ['spice'])));
    });

    test('the list is a copy and cannot be changed', () {
      final source = ['spice'];
      final s = _snapshot(lemmas: source);
      source.add('flow');
      expect(s.lemmas, ['spice']);
      expect(() => s.lemmas.add('x'), throwsUnsupportedError);
    });
  });
}
