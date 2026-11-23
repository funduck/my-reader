import 'package:core/domain_books.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'phrases_tab.dart';
import 'providers.dart';

/// History of lookups. The "Words" tab lists terms, the most recently looked
/// up first, with a counter, a short gloss and the book; a term expands to all
/// its contexts. The "Phrases" tab lists translated phrases.
class HistoryScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [onOpenLocation], if given, is called when a context
  /// with a place in a book is tapped.
  const new({this.onOpenLocation, super.key});

  /// Opens the book at the place of a lookup.
  final void Function(Locator locator)? onOpenLocation;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  BookId? _book;

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(historyProvider(_book));
    final books = ref.watch(historyBooksProvider).value ?? const <Book>[];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('History'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Words'),
              Tab(text: 'Phrases'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _words(entries, books),
            PhrasesTab(onOpenLocation: widget.onOpenLocation),
          ],
        ),
      ),
    );
  }

  Widget _words(AsyncValue<List<HistoryEntry>> entries, List<Book> books) {
    return Column(
      children: [
        if (books.isNotEmpty)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('All books', _book == null, () => _select(null)),
                for (final b in books)
                  _chip(b.metadata.title, _book == b.id, () => _select(b.id)),
              ],
            ),
          ),
        Expanded(
          child: entries.when(
            data: (items) => items.isEmpty
                ? const Center(child: Text('No lookups yet.'))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => _TermTile(
                      key: ValueKey(items[i].term.id),
                      entry: items[i],
                      onOpenLocation: widget.onOpenLocation,
                    ),
                  ),
            error: (e, _) => Center(child: Text('History is unavailable: $e')),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );

  void _select(BookId? id) => setState(() => _book = id);
}

class _TermTile extends StatelessWidget {
  const new({required this.entry, required this.onOpenLocation, super.key});

  final HistoryEntry entry;
  final void Function(Locator locator)? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    final term = entry.term;
    final book = entry.book;
    final subtitle = [
      if (entry.gloss.isNotEmpty) entry.gloss,
      if (book != null) book.metadata.title,
    ].join(' · ');
    return ExpansionTile(
      title: Text(term.normalized),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Text('×${term.lookupCount}'),
      children: [
        for (final c in entry.contexts)
          ListTile(
            dense: true,
            title: Text(c.sentence),
            subtitle: Text(formatHistoryDate(c.event.at)),
            onTap: switch ((onOpenLocation, c.event.query.locator)) {
              (final open?, final locator?) => () => open(locator),
              _ => null,
            },
          ),
      ],
    );
  }
}
