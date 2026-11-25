import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
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
    final request = (bookId: bookId, from: from);
    final load = ref.watch(cheatSheetProvider(request));
    // Subscribed with the sheet, not after it, so the list is ready at once.
    ref
      ..watch(cheatSheetProfileProvider)
      // Remembers the list on screen for the highlights in the text.
      ..watch(cheatSheetSnapshotSaverProvider(request));
    return Scaffold(
      appBar: AppBar(
        title: Text(load.maybeWhen(data: _title, orElse: () => 'Разминка')),
      ),
      body: load.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Не удалось подготовить разминку.')),
        data: (data) =>
            _Body(request: request, data: data, onWordTap: onWordTap),
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

/// Level and limit pickers above the list, then the list itself.
class _Body extends ConsumerWidget {
  const new({
    required this.request,
    required this.data,
    required this.onWordTap,
  });

  final CheatSheetRequest request;
  final CheatSheetLoad data;
  final WordTapCallback? onWordTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cheatSheetItemsProvider(request));
    final profile = ref.watch(cheatSheetProfileProvider).value;
    return Column(
      children: [
        if (profile != null) _Controls(profile: profile),
        Expanded(
          child: switch (items) {
            AsyncData(:final value) => _Items(
              request: request,
              data: data,
              items: value,
              onWordTap: onWordTap,
            ),
            AsyncError() => const Center(
              child: Text('Не удалось подготовить разминку.'),
            ),
            AsyncLoading() => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
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
    await repository.save(change(await repository.get()));
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
        ],
      ),
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
  });

  final CheatSheetRequest request;
  final CheatSheetLoad data;
  final List<CheatSheetItem> items;
  final WordTapCallback? onWordTap;

  @override
  Widget build(BuildContext context) {
    final from = data.sheet?.from;
    final onWordTap = this.onWordTap;
    if (items.isEmpty) {
      return const Center(child: Text('Незнакомых слов не нашлось.'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
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
            Text(item.level.name.toUpperCase()),
          ],
          if (bars != null) ...[
            const SizedBox(width: 8),
            FrequencyBars(bars: bars),
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
      trailing: TextButton(
        key: Key('cheatsheet-known-${item.text}'),
        onPressed: () => _markKnown(context, ref),
        child: const Text('Знаю'),
      ),
    );
  }
}

/// Word frequency as signal bars: [bars] of 5 are filled, 5 is a very common
/// word. The bars grow in height, so the count reads without the colour.
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
    return Semantics(
      label: 'частотность $bars из $total',
      excludeSemantics: true,
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
