import 'package:meta/meta.dart';

import '../../../domain_books.dart';
import 'lookup_mode.dart';

/// What the user asked for.
@immutable
final class LookupQuery {
  /// Creates a query.
  const new({
    required this.text,
    required this.mode,
    this.sentence,
    this.locator,
  });

  /// Selected word or phrase.
  final String text;

  /// Lookup direction.
  final LookupMode mode;

  /// Context sentence, if known.
  final String? sentence;

  /// Place in the book, if the query came from reading.
  final Locator? locator;

  @override
  bool operator ==(Object other) =>
      other is LookupQuery &&
      other.text == text &&
      other.mode == mode &&
      other.sentence == sentence &&
      other.locator == locator;

  @override
  int get hashCode => Object.hash(text, mode, sentence, locator);
}
