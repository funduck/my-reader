import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

final Logger _log = Logger('QuickSettingsSheet');

/// The highlight preferences of the saved profile, updated on every change.
final StreamProvider<HighlightPrefs> highlightPrefsProvider =
    StreamProvider.autoDispose<HighlightPrefs>(
      (ref) => ref
          .watch(profileRepositoryProvider)
          .watch()
          .map((profile) => profile.highlights)
          .distinct(),
      name: 'highlightPrefsProvider',
    );

/// Bottom sheet with the quick text settings: size, spacing, dimming and
/// the highlights.
///
/// Reads the current display preferences from [display] and reports every
/// change through [onChanged]; the owner updates [display] and saves with a
/// delay. The highlight switches read and save the profile themselves, at
/// once, like the "Day / Night" button.
class QuickSettingsSheet extends StatelessWidget {
  /// Creates the sheet.
  const new({required this.display, required this.onChanged, super.key});

  /// Current preferences; the sheet rebuilds when they change.
  final ValueListenable<DisplayPrefs> display;

  /// Called with the changed preferences.
  final ValueChanged<DisplayPrefs> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: ValueListenableBuilder<DisplayPrefs>(
          valueListenable: display,
          builder: (context, prefs, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Font size')),
                    OutlinedButton(
                      onPressed: prefs.fontSize <= DisplayPrefs.minFontSize
                          ? null
                          : () => onChanged(
                              prefs.copyWith(fontSize: prefs.fontSize - 1),
                            ),
                      child: const Text('A−'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(prefs.fontSize.round().toString()),
                    ),
                    OutlinedButton(
                      onPressed: prefs.fontSize >= DisplayPrefs.maxFontSize
                          ? null
                          : () => onChanged(
                              prefs.copyWith(fontSize: prefs.fontSize + 1),
                            ),
                      child: const Text('A+'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Line spacing'),
                Slider(
                  key: const Key('line-height'),
                  min: 1,
                  max: 2.5,
                  divisions: 15,
                  value: prefs.lineHeight.clamp(1, 2.5),
                  label: prefs.lineHeight.toStringAsFixed(1),
                  onChanged: (v) => onChanged(
                    prefs.copyWith(lineHeight: (v * 10).round() / 10),
                  ),
                ),
                const Text('Dimming'),
                Slider(
                  key: const Key('dim'),
                  max: DisplayPrefs.maxDim,
                  divisions: 16,
                  value: prefs.dim.clamp(0, DisplayPrefs.maxDim),
                  label: prefs.dim.toStringAsFixed(2),
                  onChanged: (v) =>
                      onChanged(prefs.copyWith(dim: (v * 20).round() / 20)),
                ),
                const SizedBox(height: 8),
                const _HighlightsSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Switches of the text highlights: all at once and each kind.
class _HighlightsSection extends ConsumerWidget {
  const new();

  /// Saves [change] applied to the stored highlight preferences.
  Future<void> _save(
    WidgetRef ref,
    HighlightPrefs Function(HighlightPrefs) change,
  ) async {
    final repository = ref.read(profileRepositoryProvider);
    try {
      await repository.update(
        (profile) => profile.copyWith(highlights: change(profile.highlights)),
      );
    } on Object catch (e, s) {
      _log.severe('Saving the highlight settings failed', e, s);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(highlightPrefsProvider).value;
    // Until the profile arrives every switch is off and inactive.
    final loaded = prefs != null;
    final p = prefs ?? const HighlightPrefs(enabled: false);
    final kindsOn = loaded && p.enabled;

    Widget kind(
      Key key,
      String label,
      bool value,
      HighlightPrefs Function(HighlightPrefs, bool) apply,
    ) => SwitchListTile(
      key: key,
      dense: true,
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 0),
      title: Text(label),
      value: value,
      onChanged: kindsOn
          ? (v) => unawaited(_save(ref, (h) => apply(h, v)))
          : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('highlights-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Highlights'),
          value: p.enabled,
          onChanged: loaded
              ? (v) => unawaited(_save(ref, (h) => h.copyWith(enabled: v)))
              : null,
        ),
        kind(
          const Key('highlight-difficult'),
          'Difficult words',
          p.difficult,
          (h, v) => h.copyWith(difficult: v),
        ),
        kind(
          const Key('highlight-cheat-sheet'),
          'Cheat sheet',
          p.cheatSheet,
          (h, v) => h.copyWith(cheatSheet: v),
        ),
        kind(
          const Key('highlight-looked-up'),
          'Looked up',
          p.lookedUp,
          (h, v) => h.copyWith(lookedUp: v),
        ),
        kind(
          const Key('highlight-recent'),
          'Just translated',
          p.recent,
          (h, v) => h.copyWith(recent: v),
        ),
      ],
    );
  }
}
