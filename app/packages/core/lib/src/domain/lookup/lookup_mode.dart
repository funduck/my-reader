/// Direction of a lookup.
enum LookupMode {
  /// English to Russian translation.
  enRu,

  /// English to English definition, like a monolingual dictionary.
  enEn;

  /// Parses [name] (the enum name); returns [fallback] for null or unknown.
  static LookupMode fromJson(
    Object? name, {
    LookupMode fallback = LookupMode.enEn,
  }) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  /// JSON form: the enum name.
  String toJson() => name;
}
