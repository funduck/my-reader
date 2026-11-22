import 'package:core/domain_lookup.dart';
import 'package:test/test.dart';

void main() {
  const ordered = [
    CefrLevel.a1,
    CefrLevel.a2,
    CefrLevel.b1,
    CefrLevel.b2,
    CefrLevel.c1,
    CefrLevel.c2,
  ];

  test('known levels are ordered a1 < ... < c2', () {
    for (var i = 0; i < ordered.length; i++) {
      for (var j = 0; j < ordered.length; j++) {
        expect(ordered[i] < ordered[j], i < j, reason: '$i < $j');
        expect(ordered[i] > ordered[j], i > j, reason: '$i > $j');
        expect(ordered[i] <= ordered[j], i <= j, reason: '$i <= $j');
        expect(ordered[i] >= ordered[j], i >= j, reason: '$i >= $j');
        expect(ordered[i].isHarderThan(ordered[j]), i > j);
        expect(ordered[i].isAtLeast(ordered[j]), i >= j);
        expect(ordered[i].compareTo(ordered[j]).sign, (i - j).sign);
      }
    }
  });

  test('unknown is incomparable with everything, itself included', () {
    const u = CefrLevel.unknown;
    for (final level in [...ordered, u]) {
      expect(u < level, isFalse);
      expect(u > level, isFalse);
      expect(u <= level, isFalse);
      expect(u >= level, isFalse);
      expect(level < u, isFalse);
      expect(level > u, isFalse);
      expect(level <= u, isFalse);
      expect(level >= u, isFalse);
      expect(() => u.compareTo(level), throwsStateError);
      expect(() => level.compareTo(u), throwsStateError);
    }
    expect(u.isKnown, isFalse);
  });

  test('JSON uses lower-case names and falls back to unknown', () {
    expect(CefrLevel.values.map((e) => e.toJson()), [
      'a1',
      'a2',
      'b1',
      'b2',
      'c1',
      'c2',
      'unknown',
    ]);
    for (final level in CefrLevel.values) {
      expect(CefrLevel.fromJson(level.toJson()), level);
    }
    expect(CefrLevel.fromJson('C1'), CefrLevel.unknown);
    expect(CefrLevel.fromJson(null), CefrLevel.unknown);
    expect(CefrLevel.fromJson(5), CefrLevel.unknown);
  });
}
