import 'dart:typed_data';

import '../domain/books/book.dart';
import '../domain/books/chapter_ref.dart';
import '../domain/books/content_document.dart';
import '../domain/books/toc_entry.dart';

/// Opens one or more book formats (R-1).
///
/// Files are addressed by absolute filesystem path. Methods throw
/// [FormatException] when the file is not a valid book of this format.
abstract interface class BookFormatAdapter {
  /// Formats this adapter can open.
  Set<BookFormat> get formats;

  /// Returns whether the file at [path] looks like a book this adapter opens.
  ///
  /// Never throws for unreadable or foreign files; returns false instead.
  Future<bool> canOpen(String path);

  /// Reads title, author and language without opening the whole book.
  Future<BookMetadata> readMetadata(String path);

  /// Opens the book; the caller must [OpenedBook.close] it.
  Future<OpenedBook> open(String path);
}

/// An open book: its structure, chapters and resources.
abstract interface class OpenedBook {
  /// Table of contents, nested.
  List<TocEntry> get toc;

  /// Chapters in reading order.
  List<ChapterRef> get spine;

  /// Parses one chapter into the intermediate representation.
  Future<ContentDocument> chapter(ChapterRef ref);

  /// Returns the bytes of a resource (image, font) by its [href].
  Future<Uint8List> resource(String href);

  /// Releases files and memory; the object is unusable afterwards.
  Future<void> close();
}
