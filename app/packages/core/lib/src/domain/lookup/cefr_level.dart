/// CEFR level of a word or of a reader.
///
/// Values are lower-case names matching the service `cefr` column
/// (`a1`..`c2`). Order: `a1 < a2 < b1 < b2 < c1 < c2`.
///
/// [unknown] is outside the order: every comparison operator and
/// [isHarderThan]/[isAtLeast] returns `false` when either side is [unknown].
/// Callers decide what an unknown word means (for example the cheat sheet
/// may choose to show it). [compareTo] throws [StateError] on [unknown].
enum CefrLevel implements Comparable<CefrLevel> {
  /// Beginner.
  a1,

  /// Elementary.
  a2,

  /// Intermediate.
  b1,

  /// Upper intermediate.
  b2,

  /// Advanced.
  c1,

  /// Proficient.
  c2,

  /// Level is not known; incomparable with every level including itself.
  unknown;

  /// Whether this level has a place in the a1..c2 order.
  bool get isKnown => this != unknown;

  /// Whether this level is strictly harder than [other]; false if either is
  /// [unknown].
  bool isHarderThan(CefrLevel other) =>
      isKnown && other.isKnown && index > other.index;

  /// Whether this level is [other] or harder; false if either is [unknown].
  bool isAtLeast(CefrLevel other) =>
      isKnown && other.isKnown && index >= other.index;

  /// Same as [isHarderThan].
  bool operator >(CefrLevel other) => isHarderThan(other);

  /// Same as [isAtLeast].
  bool operator >=(CefrLevel other) => isAtLeast(other);

  /// Whether this level is strictly easier than [other]; false if either is
  /// [unknown].
  bool operator <(CefrLevel other) => other.isHarderThan(this);

  /// Whether this level is [other] or easier; false if either is [unknown].
  bool operator <=(CefrLevel other) => other.isAtLeast(this);

  @override
  int compareTo(CefrLevel other) {
    if (!isKnown || !other.isKnown) {
      throw StateError('CefrLevel.unknown is not comparable');
    }
    return index - other.index;
  }

  /// Parses a lower-case name; returns [unknown] for null or unrecognised.
  static CefrLevel fromJson(Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return unknown;
  }

  /// JSON form: the enum name.
  String toJson() => name;
}
