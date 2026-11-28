import 'package:meta/meta.dart';

import '../books/ids.dart';

/// Which screen of a book the app reopens at launch.
enum LastScreenKind {
  /// The reader, at the saved position of the book.
  reader,

  /// The cheat sheet of the book, built anew.
  cheatsheet;

  /// Name in JSON.
  String toJson() => name;
}

/// The last screen the user was on: the reader or the cheat sheet of a book.
///
/// Only the screen is kept. The reading position is the book's own progress,
/// and the cheat sheet is built again. Library, history and settings are
/// never stored: the library is "no last screen", the others do not change it.
@immutable
final class LastScreen {
  /// Creates the record.
  const new({required this.kind, required this.book});

  /// Reads a record; `null` for anything that is not a valid record.
  static LastScreen? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final kind = json['kind'];
    final book = json['book'];
    if (kind is! String || book is! String || book.isEmpty) return null;
    for (final k in LastScreenKind.values) {
      if (k.name == kind) return LastScreen(kind: k, book: BookId(book));
    }
    return null;
  }

  /// The kind of the screen.
  final LastScreenKind kind;

  /// The book of the screen.
  final BookId book;

  /// JSON form.
  Map<String, Object?> toJson() => {'kind': kind.toJson(), 'book': book.value};

  @override
  bool operator ==(Object other) =>
      other is LastScreen && other.kind == kind && other.book == book;

  @override
  int get hashCode => Object.hash(kind, book);

  @override
  String toString() => 'LastScreen(${kind.name}, ${book.value})';
}
