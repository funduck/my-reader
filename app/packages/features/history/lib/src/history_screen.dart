import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'phrases_tab.dart';
import 'providers.dart';

/// History of lookups. The "Words" tab lists terms, the most recently looked
/// up first, with a counter and the book (no translation: dictionary senses
/// may hold markup); a term expands to all its contexts. A "Знаю" filter shows
/// the terms marked known, also those never looked up (marked from the cheat
/// sheet); a known term has a check button that takes the mark off, with
/// "Undo". The "Phrases" tab lists translated phrases.
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
  bool _knownOnly = false;

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
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 10,
                ),
                child: FilterChip(
                  key: const Key('history-known-filter'),
                  label: const Text('Знаю'),
                  selected: _knownOnly,
                  onSelected: (on) => setState(() => _knownOnly = on),
                ),
              ),
              if (books.isNotEmpty) ...[
                _chip('All books', _book == null, () => _select(null)),
                for (final b in books)
                  _chip(b.metadata.title, _book == b.id, () => _select(b.id)),
              ],
            ],
          ),
        ),
        Expanded(
          child: entries.when(
            data: (all) {
              final items = [
                for (final e in all)
                  if (!_knownOnly || e.term.status == TermStatus.known) e,
              ];
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    _knownOnly ? 'No known words.' : 'No lookups yet.',
                  ),
                );
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _TermTile(
                  key: ValueKey(items[i].term.id),
                  entry: items[i],
                  onOpenLocation: widget.onOpenLocation,
                ),
              );
            },
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

class _TermTile extends ConsumerWidget {
  const new({required this.entry, required this.onOpenLocation, super.key});

  static final Logger _log = Logger('HistoryScreen');

  final HistoryEntry entry;
  final void Function(Locator locator)? onOpenLocation;

  /// Takes the "known" mark off and offers to put it back. The row leaves the
  /// list as soon as the term changes, so everything the "Undo" needs is
  /// captured before.
  void _unmark(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    final setStatus = ref.read(setTermStatusProvider);
    final word = entry.term.normalized;
    final language = entry.term.language;
    Future<void> set(TermStatus status) async {
      try {
        await setStatus(word, status, language: language);
      } on Object catch (error, stack) {
        _log.warning('Marking "$word" failed', error, stack);
      }
    }

    unawaited(set(TermStatus.learning));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('«Знаю» снято: $word'),
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(set(TermStatus.known)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = entry.term;
    final book = entry.book;
    final known = term.status == TermStatus.known;
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (term.lookupCount > 0) Text('×${term.lookupCount}'),
        if (known)
          IconButton(
            key: const Key('history-unmark-known'),
            icon: const Icon(Icons.check_circle),
            tooltip: 'Снять «Знаю»',
            onPressed: () => _unmark(context, ref),
          ),
      ],
    );
    final subtitle = book == null ? null : Text(book.metadata.title);
    if (entry.contexts.isEmpty) {
      return ListTile(
        title: Text(term.normalized),
        subtitle: subtitle,
        trailing: trailing,
      );
    }
    return ExpansionTile(
      title: Text(term.normalized),
      subtitle: subtitle,
      trailing: trailing,
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
