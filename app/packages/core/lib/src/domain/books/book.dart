import 'package:meta/meta.dart';

import 'ids.dart';

/// File format of a book.
enum BookFormat {
  /// EPUB.
  epub,

  /// FictionBook 2.
  fb2,

  /// Plain text.
  txt,

  /// PDF.
  pdf,
}

/// Descriptive data of a book.
@immutable
final class BookMetadata {
  /// Creates metadata; [author] and [language] may be unknown.
  const new({required this.title, this.author, this.language});

  /// Title of the book.
  final String title;

  /// Author, if the file names one.
  final String? author;

  /// BCP 47 language tag of the text, if the file names one.
  final String? language;

  /// Returns a copy with the given fields replaced.
  BookMetadata copyWith({String? title, String? author, String? language}) =>
      BookMetadata(
        title: title ?? this.title,
        author: author ?? this.author,
        language: language ?? this.language,
      );

  @override
  bool operator ==(Object other) =>
      other is BookMetadata &&
      other.title == title &&
      other.author == author &&
      other.language == language;

  @override
  int get hashCode => Object.hash(title, author, language);

  @override
  String toString() => 'BookMetadata($title)';
}

/// A book in the library.
@immutable
final class Book {
  /// Creates a book.
  const new({
    required this.id,
    required this.metadata,
    required this.format,
    required this.filePath,
    required this.contentHash,
    required this.addedAt,
  });

  /// Library identifier.
  final BookId id;

  /// Title, author, language.
  final BookMetadata metadata;

  /// File format.
  final BookFormat format;

  /// Path of the book file on the device.
  final String filePath;

  /// Hash of the file content, used to detect duplicates.
  final String contentHash;

  /// When the book was added to the library.
  final DateTime addedAt;

  /// Returns a copy with the given fields replaced.
  Book copyWith({
    BookId? id,
    BookMetadata? metadata,
    BookFormat? format,
    String? filePath,
    String? contentHash,
    DateTime? addedAt,
  }) => Book(
    id: id ?? this.id,
    metadata: metadata ?? this.metadata,
    format: format ?? this.format,
    filePath: filePath ?? this.filePath,
    contentHash: contentHash ?? this.contentHash,
    addedAt: addedAt ?? this.addedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Book &&
      other.id == id &&
      other.metadata == metadata &&
      other.format == format &&
      other.filePath == filePath &&
      other.contentHash == contentHash &&
      other.addedAt == addedAt;

  @override
  int get hashCode =>
      Object.hash(id, metadata, format, filePath, contentHash, addedAt);

  @override
  String toString() => 'Book($id, ${metadata.title})';
}
