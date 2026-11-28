import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import 'providers.dart';

/// Called when the user taps a word of the list; opens the lookup sheet.
typedef WordTapCallback = void Function(
  BuildContext context,
  LookupQuery query,
);

final Logger _log = Logger('CheatSheetScreen');

/// The levels offered for "above": a word of the top level has nothing above.
/// Page counts offered for the piece; the same as in the settings (features
/// do not import each other, so the list is repeated there).
const List<int> _pageChoices = [1, 2, 3, 5, 10, 15, 20, 30];

const List<CefrLevel> _pickableLevels = [
  CefrLevel.a2,
  CefrLevel.b1,
  CefrLevel.b2,
  CefrLevel.c1,
];

/// Warm-up before reading: the hard words of the next piece of [bookId], each
/// with its level, frequency, a short meaning and a quote from the text.
///
/// The piece starts at [from], or at the saved position when it is null.
/// Above the list the user picks the level and how many words to show (both
/// saved in the profile); "Знаю" hides a word and marks its term known.
/// Tapping a word calls [onWordTap] (the app shows the lookup sheet, which
/// writes the query to the history). The "Читать" button ends the list: it
/// saves the shown list to the cheat-sheet log (only this way, B-027), waits
/// for the write, then calls [onRead], which brings the user back to the
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

  /// Called by the "Читать" button, after the shown list is saved.
  final VoidCallback onRead;

  /// Called when a word is tapped; without it the rows are not tappable.
  final WordTapCallback? onWordTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = (bookId: bookId, from: from);
    final load = ref.watch(cheatSheetProvider(request));
    // Subscribed with the sheet, not after it, so the list is ready at once.
    final profile = ref.watch(cheatSheetProfileProvider).value;
    // The title follows the profile: a new piece size shows while the sheet
    // is being built again.
    final scope = profile?.scope ?? load.value?.scope;
    return Scaffold(
      appBar: AppBar(title: Text(scope == null ? 'Разминка' : _title(scope))),
      body: Column(
        children: [
          // Above the sheet, not inside it: they stay while it is rebuilt.
          if (profile != null) _Controls(profile: profile),
          Expanded(
            child: load.when(
              loading: () => _ListWithRead(
                onRead: () => _read(context, ref, request),
                child: const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, _) => _ListWithRead(
                onRead: () => _read(context, ref, request),
                child: const _Message('Не удалось подготовить разминку.'),
              ),
              data: (data) => _Body(
                request: request,
                data: data,
                onWordTap: onWordTap,
                onRead: () => _read(context, ref, request),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Remembers the list on screen (for the highlights in the text), then goes
  /// to the reader. The write is awaited so the reader sees the new snapshot.
  Future<void> _read(
    BuildContext context,
    WidgetRef ref,
    CheatSheetRequest request,
  ) async {
    final container = ProviderScope.containerOf(context);
    await saveShownCheatSheet(container, request);
    if (context.mounted) onRead();
  }

  static String _title(CheatSheetScope scope) => switch (scope) {
    CheatSheetPages(:final pages) => 'Следующие ~$pages стр.',
    CheatSheetChapter() => 'До конца главы',
  };
}

/// The list of the built sheet.
class _Body extends ConsumerWidget {
  const new({
    required this.request,
    required this.data,
    required this.onWordTap,
    required this.onRead,
  });

  final CheatSheetRequest request;
  final CheatSheetLoad data;
  final WordTapCallback? onWordTap;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(cheatSheetItemsProvider(request))) {
      AsyncData(:final value) => _Items(
        request: request,
        data: data,
        items: value,
        onWordTap: onWordTap,
        onRead: onRead,
      ),
      AsyncError() => _ListWithRead(
        onRead: onRead,
        child: const _Message('Не удалось подготовить разминку.'),
      ),
      AsyncLoading() => _ListWithRead(
        onRead: onRead,
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    };
  }
}

/// Saves the change of the profile; the level and the limit are the same
/// values as in the settings.
Future<void> _updateProfile(
  WidgetRef ref,
  UserProfile Function(UserProfile) change,
) async {
  try {
    final repository = ref.read(profileRepositoryProvider);
    await repository.update(change);
  } on Object catch (error, stack) {
    _log.warning('Cannot save the profile', error, stack);
  }
}

class _Controls extends ConsumerWidget {
  const new({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Выше уровня'),
              const SizedBox(width: 8),
              SegmentedButton<CefrLevel>(
                key: const Key('cheatsheet-level'),
                showSelectedIcon: false,
                emptySelectionAllowed: true,
                segments: [
                  for (final level in _pickableLevels)
                    ButtonSegment(
                      value: level,
                      label: Text(level.name.toUpperCase()),
                    ),
                ],
                selected: {
                  if (_pickableLevels.contains(profile.level)) profile.level,
                },
                onSelectionChanged: (s) => unawaited(
                  _updateProfile(ref, (p) => p.copyWith(level: s.first)),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Слов'),
              const SizedBox(width: 8),
              _LimitField(limit: profile.cheatSheetLimit),
            ],
          ),
          _ScopeControl(scope: profile.scope),
        ],
      ),
    );
  }
}

/// The piece of text the sheet covers: a number of pages or the rest of the
/// chapter. The same value as "Cheat sheet piece" in the settings; a change
/// builds the sheet again.
class _ScopeControl extends ConsumerWidget {
  const new({required this.scope});

  final CheatSheetScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = switch (scope) {
      CheatSheetPages(:final pages) => pages,
      CheatSheetChapter() => null,
    };
    final choices = {..._pageChoices, ?pages}.toList()..sort();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<bool>(
          key: const Key('cheatsheet-scope'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Страниц')),
            ButtonSegment(value: false, label: Text('До конца главы')),
          ],
          selected: {pages != null},
          onSelectionChanged: (s) => unawaited(
            _updateProfile(
              ref,
              (p) => p.copyWith(
                scope: s.first
                    ? CheatSheetScope.defaultScope
                    : const CheatSheetChapter(),
              ),
            ),
          ),
        ),
        if (pages != null) ...[
          const SizedBox(width: 8),
          DropdownButton<int>(
            key: const Key('cheatsheet-pages'),
            value: pages,
            items: [
              for (final n in choices)
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: (n) {
              if (n != null && n != pages) {
                unawaited(
                  _updateProfile(
                    ref,
                    (p) => p.copyWith(scope: CheatSheetPages(n)),
                  ),
                );
              }
            },
          ),
        ],
      ],
    );
  }
}

/// The number of words: digits only, saved when the focus leaves the field or
/// on Enter. An empty or zero value goes back to the saved number; more than
/// the maximum becomes the maximum.
class _LimitField extends ConsumerStatefulWidget {
  const new({required this.limit});

  final int limit;

  @override
  ConsumerState<_LimitField> createState() => _LimitFieldState();
}

class _LimitFieldState extends ConsumerState<_LimitField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.limit}',
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  /// Shows [value] as the field text, cursor at the end.
  void _show(int value) {
    final text = '$value';
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _commit() {
    final entered = int.tryParse(_controller.text);
    if (entered == null || entered < minCheatSheetLimit) {
      _show(widget.limit);
      return;
    }
    final value = entered > maxCheatSheetLimit ? maxCheatSheetLimit : entered;
    _show(value);
    if (value != widget.limit) {
      unawaited(_updateProfile(ref, (p) => p.copyWith(cheatSheetLimit: value)));
    }
  }

  @override
  void didUpdateWidget(_LimitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.limit != widget.limit && !_focus.hasFocus) {
      _show(widget.limit);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: TextField(
        key: const Key('cheatsheet-limit'),
        controller: _controller,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        decoration: const InputDecoration(isDense: true),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const new({
    required this.request,
    required this.data,
    required this.items,
    required this.onWordTap,
    required this.onRead,
  });

  final CheatSheetRequest request;
  final CheatSheetLoad data;
  final List<CheatSheetItem> items;
  final WordTapCallback? onWordTap;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final from = data.sheet?.from;
    final onWordTap = this.onWordTap;
    if (items.isEmpty) {
      return _ListWithRead(
        onRead: onRead,
        child: const _Message('Незнакомых слов не нашлось.'),
      );
    }
    return ListView.builder(
      // The last entry is the "Читать" button, after the last row.
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == items.length) return _ReadButton(onRead: onRead);
        final item = items[i];
        return _ItemTile(
          key: ValueKey(item.text),
          request: request,
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
                    locator: from,
                  ),
                ),
        );
      },
    );
  }
}

/// A [child] (a message or a spinner) followed by the "Читать" button, for the
/// states without rows: the button is there whatever the sheet holds.
class _ListWithRead extends StatelessWidget {
  const new({required this.child, required this.onRead});

  final Widget child;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        child,
        _ReadButton(onRead: onRead),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(child: Text(text)),
  );
}

/// The end of the list: saves the shown list, then goes to the reader.
class _ReadButton extends StatelessWidget {
  const new({required this.onRead});

  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(onPressed: onRead, child: const Text('Читать')),
      ),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const new({
    required this.request,
    required this.item,
    required this.mode,
    required this.onTap,
    super.key,
  });

  final CheatSheetRequest request;
  final CheatSheetItem item;
  final LookupMode mode;
  final VoidCallback? onTap;

  /// Hides the row and offers to bring it back. What "Undo" needs is captured
  /// first: the row is gone from the list by then.
  void _markKnown(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    final known = ref.read(cheatSheetKnownProvider(request).notifier);
    unawaited(known.markKnown(item));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('«Знаю»: ${item.text}'),
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(known.undo(item)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gloss =
        item.translation ??
        ref.watch(itemGlossProvider((text: item.text, mode: mode))).value;
    final theme = Theme.of(context);
    final example = item.example;
    final bars = zipfBars(item.zipf);
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Flexible(child: Text(item.text, style: theme.textTheme.titleMedium)),
          if (item.level.isKnown) ...[
            const SizedBox(width: 8),
            LevelBadge(level: WordLevel(item.level)),
          ],
          if (bars != null) ...[
            const SizedBox(width: 8),
            FrequencyBars(bars: bars),
          ],
          if (item.lookupCount > 0) ...[
            const SizedBox(width: 8),
            LookedUpMark(
              key: Key('cheatsheet-looked-up-${item.text}'),
              count: item.lookupCount,
            ),
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
      // A button, not a label: it acts on the row, so it has a border and
      // a check mark.
      trailing: OutlinedButton.icon(
        key: Key('cheatsheet-known-${item.text}'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: () => _markKnown(context, ref),
        icon: const Icon(Icons.check, size: 18),
        label: const Text('Знаю'),
      ),
    );
  }
}

/// The mark of a word the user translated before (T-121): a translate icon
/// and the number of lookups as `×N`.
///
/// An [InfoLabel]: the icon and the number carry the meaning without colour;
/// a screen reader reads one phrase instead of the two pieces.
class LookedUpMark extends StatelessWidget {
  /// Creates the mark for a word looked up [count] times (above 0).
  const new({required this.count, super.key});

  /// How many times the word was looked up.
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InfoLabel(
      semanticsLabel: 'переводил: $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.translate, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 2),
          Text('×$count'),
        ],
      ),
    );
  }
}

/// Word frequency as signal bars in an [InfoLabel]: [bars] of 5 are filled,
/// 5 is a very common word. The bars grow in height, so the count reads
/// without the colour.
class FrequencyBars extends StatelessWidget {
  /// Creates the bars; [bars] is from 1 to 5.
  const new({required this.bars, super.key});

  /// How many bars are filled, 1..5.
  final int bars;

  /// The number of bars drawn.
  static const int total = 5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InfoLabel(
      semanticsLabel: 'частотность $bars из $total',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= total; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 2),
              child: Container(
                width: 3,
                height: 3.0 + 2 * i,
                decoration: BoxDecoration(
                  color: i <= bars ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
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
