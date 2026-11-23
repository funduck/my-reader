import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'providers.dart';

/// The "Phrases" tab: translated phrases, the newest first. A phrase is
/// deleted by swiping it away, with an "Undo" in a snack bar.
class PhrasesTab extends ConsumerStatefulWidget {
  /// Creates the tab; [onOpenLocation], if given, is called when a phrase is
  /// tapped.
  const new({this.onOpenLocation, super.key});

  /// Opens the book at the place of a phrase.
  final void Function(Locator locator)? onOpenLocation;

  @override
  ConsumerState<PhrasesTab> createState() => _PhrasesTabState();
}

class _PhrasesTabState extends ConsumerState<PhrasesTab> {
  /// Phrases swiped away whose deletion the journal has not reported yet: a
  /// dismissed row must leave the tree at once.
  final Set<PhraseLookupId> _hidden = {};

  Future<void> _delete(PhraseLookup phrase) async {
    final messenger = ScaffoldMessenger.of(context);
    final journal = ref.read(phraseJournalProvider);
    setState(() => _hidden.add(phrase.id));
    await journal.delete(phrase.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Phrase deleted'),
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _undo(journal, phrase),
          ),
        ),
      );
  }

  Future<void> _undo(PhraseJournal journal, PhraseLookup phrase) async {
    // The entry is gone, so recording it again restores it with its id.
    await journal.record(phrase);
    if (mounted) setState(() => _hidden.remove(phrase.id));
  }

  @override
  Widget build(BuildContext context) {
    final phrases = ref.watch(historyPhrasesProvider);
    final books = ref.watch(historyBooksProvider).value ?? const <Book>[];
    final titles = {for (final b in books) b.id: b.metadata.title};
    return phrases.when(
      data: (all) {
        final items = [
          for (final p in all)
            if (!_hidden.contains(p.id)) p,
        ];
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Select several words while reading to translate a phrase',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) {
            final p = items[i];
            return Dismissible(
              key: ValueKey(p.id),
              onDismissed: (_) => _delete(p),
              child: _PhraseTile(
                phrase: p,
                bookTitle: titles[p.locator.book],
                onOpenLocation: widget.onOpenLocation,
              ),
            );
          },
        );
      },
      error: (e, _) => Center(child: Text('Phrases are unavailable: $e')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _PhraseTile extends StatelessWidget {
  const new({
    required this.phrase,
    required this.bookTitle,
    required this.onOpenLocation,
  });

  final PhraseLookup phrase;
  final String? bookTitle;
  final void Function(Locator locator)? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    final open = onOpenLocation;
    final sentence = phrase.sentence;
    final meta = [?bookTitle, formatHistoryDate(phrase.at)].join(' · ');
    return ListTile(
      title: Text(phrase.text),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(phrase.translation),
          Text(meta),
          if (sentence != null)
            Text(
              sentence,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      isThreeLine: true,
      onTap: open == null ? null : () => open(phrase.locator),
    );
  }
}
