import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

final Logger _log = Logger('HighlightsSection');

Future<void> _updateHighlights(
  WidgetRef ref,
  HighlightPrefs Function(HighlightPrefs) change,
) async {
  final repository = ref.read(profileRepositoryProvider);
  try {
    final profile = await repository.get();
    await repository.save(
      profile.copyWith(highlights: change(profile.highlights)),
    );
  } on Object catch (e, s) {
    _log.severe('Cannot save the highlight settings', e, s);
  }
}

/// The "Highlights" section: the switches of the text highlights and the
/// frequency threshold shared with the cheat sheet.
class HighlightsSection extends ConsumerWidget {
  /// Creates the section for the current [highlights] preferences.
  const new({required this.highlights, super.key});

  /// Current highlight preferences.
  final HighlightPrefs highlights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kindsOn = highlights.enabled;

    Widget kind(
      Key key,
      String label,
      bool value,
      HighlightPrefs Function(HighlightPrefs, bool) apply,
    ) => SwitchListTile(
      key: key,
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 0),
      title: Text(label),
      value: value,
      onChanged: kindsOn
          ? (v) => unawaited(_updateHighlights(ref, (h) => apply(h, v)))
          : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Highlights', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          key: const Key('highlights-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Highlight words in the text'),
          value: highlights.enabled,
          onChanged: (v) =>
              unawaited(_updateHighlights(ref, (h) => h.copyWith(enabled: v))),
        ),
        kind(
          const Key('highlight-difficult'),
          'Difficult words',
          highlights.difficult,
          (h, v) => h.copyWith(difficult: v),
        ),
        kind(
          const Key('highlight-cheat-sheet'),
          'Cheat sheet',
          highlights.cheatSheet,
          (h, v) => h.copyWith(cheatSheet: v),
        ),
        kind(
          const Key('highlight-looked-up'),
          'Looked up',
          highlights.lookedUp,
          (h, v) => h.copyWith(lookedUp: v),
        ),
        kind(
          const Key('highlight-recent'),
          'Just translated',
          highlights.recent,
          (h, v) => h.copyWith(recent: v),
        ),
        const SizedBox(height: 12),
        const Text('Word frequency threshold'),
        const SizedBox(height: 4),
        Text(
          'Words with fewer bars are left out of the cheat sheet and the '
          'difficult words highlight. One bar leaves everything in.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        FrequencyThreshold(
          bars: highlights.minFrequencyBars,
          onChanged: (bars) => unawaited(
            _updateHighlights(ref, (h) => h.copyWith(minFrequencyBars: bars)),
          ),
        ),
      ],
    );
  }
}

/// Five frequency bars, the same as in the cheat sheet, that pick a threshold
/// by a tap: the bars up to [bars] are filled.
///
/// The bars grow in height, so the value reads without the colour.
class FrequencyThreshold extends StatelessWidget {
  /// Creates the picker; [bars] is from [minHighlightBars] to
  /// [maxHighlightBars].
  const new({required this.bars, required this.onChanged, super.key});

  /// The chosen threshold, 1..5.
  final int bars;

  /// Called with the tapped bar number.
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = minHighlightBars; i <= maxHighlightBars; i++)
          Semantics(
            button: true,
            selected: i == bars,
            label: 'at least $i of $maxHighlightBars bars',
            excludeSemantics: true,
            onTap: () => onChanged(i),
            child: GestureDetector(
              key: Key('frequency-bar-$i'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: SizedBox(
                width: 44,
                height: 48,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      width: 3,
                      height: 3.0 + 2 * i,
                      decoration: BoxDecoration(
                        color: i <= bars
                            ? scheme.primary
                            : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
