import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'providers.dart';

/// Called when the user taps a word of the list; opens the lookup sheet.
typedef WordTapCallback = void Function(
  BuildContext context,
  LookupQuery query,
);

/// Warm-up before reading: the hard words of the next piece of [bookId], each
/// with its level, a short meaning and a sentence from the text.
///
/// The piece starts at [from], or at the saved position when it is null.
/// Tapping a word calls [onWordTap] (the app shows the lookup sheet, which
/// writes the query to the history). [onRead] brings the user back to the
/// book.
class CheatSheetScreen extends ConsumerWidget {
  /// Creates the screen.
  const new({
    required this.bookId,
    required this.onRead,
    this.from,
    this.onWordTap,
    super.key,
  });

  /// The book.
  final BookId bookId;

  /// Start of the piece; null for the saved position.
  final Locator? from;

  /// Called by the "Читать" button.
  final VoidCallback onRead;

  /// Called when a word is tapped; without it the rows are not tappable.
  final WordTapCallback? onWordTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final load = ref.watch(cheatSheetProvider((bookId: bookId, from: from)));
    return Scaffold(
      appBar: AppBar(
        title: Text(load.maybeWhen(data: _title, orElse: () => 'Разминка')),
      ),
      body: load.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Не удалось подготовить разминку.')),
        data: (data) => _Items(data: data, onWordTap: onWordTap),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: onRead, child: const Text('Читать')),
        ),
      ),
    );
  }

  static String _title(CheatSheetLoad data) => switch (data.scope) {
    CheatSheetPages(:final pages) => 'Следующие ~$pages стр.',
    CheatSheetChapter() => 'До конца главы',
  };
}

class _Items extends StatelessWidget {
  const new({required this.data, required this.onWordTap});

  final CheatSheetLoad data;
  final WordTapCallback? onWordTap;

  @override
  Widget build(BuildContext context) {
    final sheet = data.sheet;
    final onWordTap = this.onWordTap;
    if (sheet == null || sheet.items.isEmpty) {
      return const Center(child: Text('Незнакомых слов не нашлось.'));
    }
    return ListView.builder(
      itemCount: sheet.items.length,
      itemBuilder: (context, i) {
        final item = sheet.items[i];
        return _ItemTile(
          item: item,
          mode: data.mode,
          onTap: onWordTap == null
              ? null
              : () => onWordTap(
                  context,
                  LookupQuery(
                    text: item.text,
                    mode: data.mode,
                    sentence: item.example,
                    locator: sheet.from,
                  ),
                ),
        );
      },
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const new({required this.item, required this.mode, required this.onTap});

  final CheatSheetItem item;
  final LookupMode mode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gloss =
        item.translation ??
        ref.watch(itemGlossProvider((text: item.text, mode: mode))).value;
    final theme = Theme.of(context);
    final example = item.example;
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Flexible(child: Text(item.text, style: theme.textTheme.titleMedium)),
          if (item.level.isKnown) ...[
            const SizedBox(width: 8),
            Text(item.level.name.toUpperCase()),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gloss != null && gloss.isNotEmpty) Text(gloss),
          if (example != null && example.isNotEmpty)
            Text.rich(
              highlightWord(example, item.text, theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

/// [sentence] with the first occurrence of [word] (and its ending) in bold.
///
/// [word] is a lemma, the text may hold a form of it (`run` → `running`), so
/// the match is the word as a prefix of a text word.
TextSpan highlightWord(String sentence, String word, TextStyle? base) {
  final match = RegExp(
    '(?<![\\p{L}\\p{N}])${RegExp.escape(word)}[\\p{L}\\p{N}]*',
    caseSensitive: false,
    unicode: true,
  ).firstMatch(sentence);
  if (match == null) return TextSpan(text: sentence, style: base);
  return TextSpan(
    style: base,
    children: [
      TextSpan(text: sentence.substring(0, match.start)),
      TextSpan(
        text: match.group(0),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      TextSpan(text: sentence.substring(match.end)),
    ],
  );
}
