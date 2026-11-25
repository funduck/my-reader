import 'package:meta/meta.dart';

/// Smallest frequency threshold: no filter.
const minHighlightBars = 1;

/// Largest frequency threshold.
const maxHighlightBars = 5;

bool _flag(Object? value, bool fallback) => value is bool ? value : fallback;

/// Which text highlights are on, and the frequency threshold for the
/// "difficult words" highlight and the cheat sheet.
@immutable
final class HighlightPrefs {
  /// Creates the prefs; [minFrequencyBars] is clamped to
  /// [minHighlightBars]..[maxHighlightBars].
  const new({
    this.enabled = true,
    this.difficult = false,
    this.cheatSheet = true,
    this.lookedUp = true,
    this.recent = true,
    int minFrequencyBars = minHighlightBars,
  }) : minFrequencyBars = minFrequencyBars < minHighlightBars
           ? minHighlightBars
           : minFrequencyBars > maxHighlightBars
           ? maxHighlightBars
           : minFrequencyBars;

  /// Reads the prefs; a missing or invalid field takes its default.
  factory fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const HighlightPrefs();
    final bars = json['minFrequencyBars'];
    return HighlightPrefs(
      enabled: _flag(json['enabled'], true),
      difficult: _flag(json['difficult'], false),
      cheatSheet: _flag(json['cheatSheet'], true),
      lookedUp: _flag(json['lookedUp'], true),
      recent: _flag(json['recent'], true),
      minFrequencyBars: bars is num && bars.isFinite
          ? bars.toInt()
          : minHighlightBars,
    );
  }

  /// All highlights at once.
  final bool enabled;

  /// Words harder than the reader's level.
  final bool difficult;

  /// Words of the cheat sheet.
  final bool cheatSheet;

  /// Words and phrases already looked up.
  final bool lookedUp;

  /// The latest lookup.
  final bool recent;

  /// Words with fewer frequency bars (1..5) are left out; 1 is no filter.
  final int minFrequencyBars;

  /// Copy with some fields replaced.
  HighlightPrefs copyWith({
    bool? enabled,
    bool? difficult,
    bool? cheatSheet,
    bool? lookedUp,
    bool? recent,
    int? minFrequencyBars,
  }) => HighlightPrefs(
    enabled: enabled ?? this.enabled,
    difficult: difficult ?? this.difficult,
    cheatSheet: cheatSheet ?? this.cheatSheet,
    lookedUp: lookedUp ?? this.lookedUp,
    recent: recent ?? this.recent,
    minFrequencyBars: minFrequencyBars ?? this.minFrequencyBars,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'difficult': difficult,
    'cheatSheet': cheatSheet,
    'lookedUp': lookedUp,
    'recent': recent,
    'minFrequencyBars': minFrequencyBars,
  };

  @override
  bool operator ==(Object other) =>
      other is HighlightPrefs &&
      other.enabled == enabled &&
      other.difficult == difficult &&
      other.cheatSheet == cheatSheet &&
      other.lookedUp == lookedUp &&
      other.recent == recent &&
      other.minFrequencyBars == minFrequencyBars;

  @override
  int get hashCode => Object.hash(
    enabled,
    difficult,
    cheatSheet,
    lookedUp,
    recent,
    minFrequencyBars,
  );
}
