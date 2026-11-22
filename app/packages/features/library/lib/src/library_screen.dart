import 'dart:io';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import 'providers.dart';

final Logger _log = Logger('LibraryScreen');

/// The library: imported books with title, author and reading progress, and
/// a button that imports a new one.
class LibraryScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [onOpenBook] is called when a book is tapped.
  const new({required this.onOpenBook, super.key});

  /// Opens the reader for the book.
  final void Function(BookId id) onOpenBook;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _importing = false;

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final picker = ref.read(bookPickerProvider);
    final importBook = ref.read(importBookProvider);
    setState(() => _importing = true);
    String message;
    try {
      final path = await picker();
      if (path == null) {
        _log.fine('Import cancelled');
        return;
      }
      message = switch (await importBook(path)) {
        BookImported(:final book) => 'Added: ${book.metadata.title}',
        BookAlreadyImported(:final book) =>
          'Already in the library: ${book.metadata.title}',
        BookUnsupported() => 'This file is not a supported book.',
      };
    } on FileSystemException catch (e, s) {
      _log.warning('Import failed', e, s);
      message = 'Could not read the file: ${e.message}';
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(libraryBooksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: const Icon(Icons.add),
        label: const Text('Import book'),
      ),
      body: books.when(
        data: (items) => items.isEmpty
            ? const Center(child: Text('No books yet. Import an EPUB.'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _BookTile(
                  book: items[i],
                  onTap: () => widget.onOpenBook(items[i].id),
                ),
              ),
        error: (e, _) => Center(child: Text('Library is unavailable: $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _BookTile extends ConsumerWidget {
  const new({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = ref.watch(bookPercentProvider(book.id)).value ?? 0;
    final author = book.metadata.author;
    return ListTile(
      title: Text(book.metadata.title),
      subtitle: author == null ? null : Text(author),
      trailing: Text('${(percent * 100).round()}%'),
      onTap: onTap,
    );
  }
}
