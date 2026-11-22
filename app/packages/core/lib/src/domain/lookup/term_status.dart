/// User's relation to a term.
enum TermStatus {
  /// Being learned.
  learning,

  /// Marked as known.
  known,

  /// Ignored.
  ignored;

  /// Parses [name]; returns [fallback] for null or unknown.
  static TermStatus fromJson(
    Object? name, {
    TermStatus fallback = TermStatus.learning,
  }) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  /// JSON form: the enum name.
  String toJson() => name;
}
