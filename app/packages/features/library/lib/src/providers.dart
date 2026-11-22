import 'dart:io';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:crypto/crypto.dart';
import 'package:features_common/features_common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Directory where imported book files are stored.
///
/// Has no default: `bootstrap.dart` overrides it with a path from the OS.
final Provider<String> booksDirectoryProvider = Provider<String>(
  (ref) => throw StateError(
    'booksDirectoryProvider is not wired: override it in bootstrap.',
  ),
  name: 'booksDirectoryProvider',
);

/// Asks the user for a book file; returns its absolute path or null if the
/// dialog was cancelled. Tests override it.
final Provider<Future<String?> Function()> bookPickerProvider =
    Provider<Future<String?> Function()>(
      (ref) => pickBookFile,
      name: 'bookPickerProvider',
    );

/// The import use case, built from the shared ports.
final Provider<ImportBook> importBookProvider = Provider<ImportBook>(
  (ref) => ImportBook(
    adapters: ref.watch(bookFormatsProvider),
    books: ref.watch(bookRepositoryProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    directory: ref.watch(booksDirectoryProvider),
    hash: sha256OfFile,
  ),
  name: 'importBookProvider',
);

/// All books of the library, newest first.
final StreamProvider<List<Book>> libraryBooksProvider =
    StreamProvider<List<Book>>(
      (ref) => ref.watch(bookRepositoryProvider).watchAll(),
      name: 'libraryBooksProvider',
    );

/// Reading progress of a book as a fraction 0..1; 0 if never opened.
final StreamProvider<double> Function(BookId) bookPercentProvider =
    StreamProvider.family<double, BookId>(
      (ref, id) => ref
          .watch(progressRepositoryProvider)
          .watch(id)
          .map((progress) => progress?.percent ?? 0),
      name: 'bookPercentProvider',
    ).call;

/// Opens the system file dialog for EPUB files.
Future<String?> pickBookFile() async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'Choose a book',
    type: FileType.custom,
    allowedExtensions: const ['epub'],
  );
  return result?.files.single.path;
}

/// SHA-256 of the file at [path] as lower-case hex, read as a stream.
Future<String> sha256OfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}
