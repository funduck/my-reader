import 'package:core/application.dart';
import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'lookup_providers.dart';

/// Opens the lookup sheet for [query] and returns when it is closed.
///
/// The sheet appears at once with a skeleton and fills in when the lookup
/// finishes. The lookup is recorded in the history by `LookupSelection`.
/// [onOpenSettings] is called after the sheet closes when the user taps the
/// settings button of the "dictionary unavailable" state.
Future<void> showLookupSheet(
  BuildContext context,
  LookupQuery query, {
  VoidCallback? onOpenSettings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => LookupSheet(
      query: query,
      onOpenSettings: () {
        Navigator.of(sheetContext).pop();
        onOpenSettings?.call();
      },
    ),
  );
}

/// Content of the lookup sheet; shown by [showLookupSheet].
class LookupSheet extends ConsumerStatefulWidget {
  /// Creates the content for [query].
  const new({required this.query, this.onOpenSettings, super.key});

  /// What is looked up.
  final LookupQuery query;

  /// Called by the settings button when no dictionary is available.
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<LookupSheet> createState() => _LookupSheetState();
}

class _LookupSheetState extends ConsumerState<LookupSheet> {
  late LookupMode _mode = widget.query.mode;

  @override
  Widget build(BuildContext context) {
    final source = widget.query;
    final query = LookupQuery(
      text: source.text,
      mode: _mode,
      sentence: source.sentence,
      locator: source.locator,
    );
    final onOpenSettings = widget.onOpenSettings;
    final outcome = ref.watch(lookupOutcomeProvider(query));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                query.text,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              SegmentedButton<LookupMode>(
                segments: const [
                  ButtonSegment(value: LookupMode.enRu, label: Text('EN → RU')),
                  ButtonSegment(value: LookupMode.enEn, label: Text('EN → EN')),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (modes) =>
                    setState(() => _mode = modes.single),
              ),
              const SizedBox(height: 12),
              switch (outcome) {
                AsyncLoading() => const _Skeleton(),
                AsyncError() => _Message(
                  text: 'Something went wrong.',
                  action: TextButton(
                    onPressed: () => ref.invalidate(lookupOutcomeProvider),
                    child: const Text('Retry'),
                  ),
                ),
                AsyncData(:final value) => switch (value) {
                  LookupAnswered() => _Answer(outcome: value),
                  LookupUnanswered(isNotFound: true) => _Message(
                    text: 'Nothing found for "${query.text}".',
                  ),
                  LookupUnanswered() => _Message(
                    text:
                        'No dictionary available. '
                        'Install a dictionary pack in settings.',
                    action: FilledButton(
                      onPressed: onOpenSettings,
                      child: const Text('Open settings'),
                    ),
                  ),
                },
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width) => Container(
      width: width,
      height: 14,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Semantics(
      label: 'Loading',
      child: Column(
        key: const Key('lookup-skeleton'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bar(120), bar(260), bar(220), bar(180)],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const new({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    );
  }
}

class _Answer extends ConsumerWidget {
  const new({required this.outcome});

  final LookupAnswered outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final result = outcome.result;
    final providers = ref.watch(lookupProvidersProvider);
    var providerName = result.provider.value;
    for (final p in providers) {
      if (p.id == result.provider) providerName = p.info.name;
    }
    final transcription = result.transcription;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (transcription != null)
              Text(transcription, style: theme.textTheme.titleMedium),
            if (outcome.level.isKnown)
              Chip(label: Text(outcome.level.name.toUpperCase())),
          ],
        ),
        const SizedBox(height: 8),
        for (final (i, sense) in result.senses.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sense.partOfSpeech != null)
                  Text(
                    sense.partOfSpeech!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                Text('${i + 1}. ${sense.text}'),
                for (final example in sense.examples)
                  Text(
                    example,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        Text(providerName, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
