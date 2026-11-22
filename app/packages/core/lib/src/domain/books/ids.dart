import 'package:meta/meta.dart';

/// Identifier of a book in the library.
@immutable
final class BookId {
  /// Wraps the raw identifier [value].
  const new(this.value);

  /// Raw string form, stable across launches.
  final String value;

  @override
  bool operator ==(Object other) => other is BookId && other.value == value;

  @override
  int get hashCode => Object.hash(BookId, value);

  @override
  String toString() => 'BookId($value)';
}
