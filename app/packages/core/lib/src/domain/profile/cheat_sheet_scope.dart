import 'package:meta/meta.dart';

/// Which piece of text a cheat sheet analyses.
@immutable
sealed class CheatSheetScope {
  /// Base constructor.
  const new();

  /// Reads a scope from JSON. Missing, malformed or non-positive values give
  /// [defaultScope].
  factory fromJson(Object? json) {
    if (json is! Map<String, Object?>) return defaultScope;
    switch (json['type']) {
      case 'chapter':
        return const CheatSheetChapter();
      case 'pages':
        final pages = json['pages'];
        if (pages is int && pages > 0) return CheatSheetPages(pages);
        return defaultScope;
      default:
        return defaultScope;
    }
  }

  /// Default scope: 10 conventional pages.
  static const CheatSheetScope defaultScope = CheatSheetPages(10);

  /// JSON form: `{type: pages, pages: n}` or `{type: chapter}`.
  Map<String, Object?> toJson();
}

/// [pages] conventional pages of 300 words from the current position.
@immutable
final class CheatSheetPages extends CheatSheetScope {
  /// Creates a scope of [pages] pages; [pages] must be positive.
  const new(this.pages) : assert(pages > 0, 'pages must be > 0');

  /// Number of conventional pages.
  final int pages;

  @override
  Map<String, Object?> toJson() => {'type': 'pages', 'pages': pages};

  @override
  bool operator ==(Object other) =>
      other is CheatSheetPages && other.pages == pages;

  @override
  int get hashCode => Object.hash('pages', pages);
}

/// From the current position to the end of the chapter.
@immutable
final class CheatSheetChapter extends CheatSheetScope {
  /// Creates the scope.
  const new();

  @override
  Map<String, Object?> toJson() => {'type': 'chapter'};

  @override
  bool operator ==(Object other) => other is CheatSheetChapter;

  @override
  int get hashCode => 'chapter'.hashCode;
}
