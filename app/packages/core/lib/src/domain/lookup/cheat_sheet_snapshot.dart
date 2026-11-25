import 'package:meta/meta.dart';

import '../../../domain_books.dart';
import '../books/list_equality.dart';

/// What the cheat sheet of a [book] showed the last time: the words of the
/// list and the moment it was shown.
///
/// The words of the list are "seen in the cheat sheet" for the highlights in
/// the text. [lemmas] are `CheatSheetItem.text` of the shown rows, in the
/// order of the list; for an expression it is the whole expression.
@immutable
final class CheatSheetSnapshot {
  /// Creates a snapshot. [shownAt] should be in UTC.
  new({
    required this.book,
    required this.shownAt,
    required Iterable<String> lemmas,
  }) : lemmas = List.unmodifiable(lemmas);

  /// Restores a snapshot from [toJson] output.
  factory fromJson(Map<String, Object?> json) => CheatSheetSnapshot(
    book: BookId(json['book']! as String),
    shownAt: DateTime.fromMicrosecondsSinceEpoch(
      json['shownAt']! as int,
      isUtc: true,
    ),
    lemmas: (json['lemmas']! as List<Object?>).cast<String>(),
  );

  /// The book the cheat sheet was built for.
  final BookId book;

  /// When the list was shown.
  final DateTime shownAt;

  /// The words of the list, in the order shown; unmodifiable.
  final List<String> lemmas;

  /// Serializes the snapshot; [shownAt] is microseconds since the epoch (UTC).
  Map<String, Object?> toJson() => {
    'book': book.value,
    'shownAt': shownAt.microsecondsSinceEpoch,
    'lemmas': lemmas,
  };

  @override
  bool operator ==(Object other) =>
      other is CheatSheetSnapshot &&
      other.book == book &&
      other.shownAt == shownAt &&
      listEquals(other.lemmas, lemmas);

  @override
  int get hashCode => Object.hash(book, shownAt, listHash(lemmas));

  @override
  String toString() => 'CheatSheetSnapshot($book, ${lemmas.length} words)';
}
