import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import 'level_badge.dart';
import 'lookup_providers.dart';
import 'simple_html.dart';

/// How long a result must stay on screen before the lookup is written to the
/// history and counted in the term (T-086).
const Duration minLookupViewDuration = Duration(seconds: 2);

/// Opens the lookup sheet for [query] and returns when it is closed.
///
/// The sheet appears at once with a skeleton and fills in when the lookup
/// finishes. The lookup is recorded in the history by
/// `LookupSelection.record` once the result has been on screen for
/// [minLookupViewDuration]; closing the sheet earlier records nothing.
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

  /// Provider picked by the user; `null` is the chain in the profile order.
  ProviderId? _provider;

  @override
  Widget build(BuildContext context) {
    final source = widget.query;
    if (!isSingleWord(source.text)) {
      return _PhraseView(query: source, onOpenSettings: widget.onOpenSettings);
    }
    final original = source.mode;
    final other = _otherMode(original);
    final inOriginal = _mode == original;
    final query = LookupQuery(
      text: source.text,
      mode: _mode,
      sentence: source.sentence,
      locator: source.locator,
    );
    final onOpenSettings = widget.onOpenSettings;
    final all = ref.watch(lookupProvidersProvider);
    final candidates = [
      for (final p in all)
        if (p.supports(_mode)) p,
    ];
    // A pick that does not serve the mode (after a switch) falls back to auto.
    final provider = candidates.any((p) => p.id == _provider)
        ? _provider
        : null;

    // The chain of the opening mode stays watched, so switching back and
    // forth never repeats it.
    final base = ref.watch(
      lookupOutcomeProvider((query: source, provider: null)),
    );
    final otherQuery = LookupQuery(
      text: source.text,
      mode: other,
      sentence: source.sentence,
      locator: source.locator,
    );
    final hasOther = all.any((p) => p.supports(other));
    final probe = hasOther
        ? ref.watch(otherModeProbeProvider(otherQuery))
        : null;

    final AsyncValue<LookupOutcome> outcome;
    if (provider != null) {
      outcome = ref.watch(
        lookupOutcomeProvider((query: query, provider: provider)),
      );
    } else if (inOriginal) {
      outcome = base;
    } else {
      outcome = switch (probe) {
        AsyncData<LookupOutcome?>(value: final ready?) => AsyncData(ready),
        AsyncLoading<LookupOutcome?>() => const AsyncLoading(),
        // Nothing offline to ask, or the probe was inconclusive: ask for real.
        _ => ref.watch(
          lookupOutcomeProvider((query: otherQuery, provider: null)),
        ),
      };
    }
    final nothingInOther = switch (probe) {
      AsyncData<LookupOutcome?>(value: LookupUnanswered(isNotFound: true)) =>
        true,
      _ => false,
    };
    final level = (outcome.value ?? base.value)?.wordLevel;
    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  query.text,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (level != null) LevelBadge(level: level),
              if (hasOther) ...[
                const SizedBox(width: 8),
                _ModeToggle(
                  mode: _mode,
                  // Going back is always possible; going on is not when
                  // the other mode is known to have nothing.
                  onPressed: inOriginal && nothingInOther
                      ? null
                      : () => setState(
                          () => _mode = inOriginal ? other : original,
                        ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          switch (outcome) {
            AsyncLoading() => const _Skeleton(),
            AsyncError() => _Message(
              text: 'Something went wrong.',
              action: TextButton(
                onPressed: () => ref.invalidate(lookupOutcomeProvider),
                child: const Text('Retry'),
              ),
            ),
            AsyncData(:final value) => _RecordAfterView(
              key: ValueKey(value.event.id),
              record: () => ref.read(lookupSelectionProvider).record(value),
              child: switch (value) {
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
            ),
          },
          if (candidates.length > 1) ...[
            const SizedBox(height: 8),
            _ProviderPicker(
              providers: candidates,
              selected: provider,
              onChanged: (id) => setState(() => _provider = id),
            ),
          ],
        ],
      ),
    );
  }
}

/// Safe area, height limit and scrolling shared by both kinds of sheet.
class _SheetFrame extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
          child: child,
        ),
      ),
    );
  }
}

LookupMode _otherMode(LookupMode mode) =>
    mode == LookupMode.enRu ? LookupMode.enEn : LookupMode.enRu;

/// Compact button with the current mode (`RU` / `EN`); a press switches to the
/// other one. `onPressed: null` makes it inactive.
class _ModeToggle extends StatelessWidget {
  const new({required this.mode, required this.onPressed});

  final LookupMode mode;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final (short, full) = switch (mode) {
      LookupMode.enRu => ('RU', 'English → Russian'),
      LookupMode.enEn => ('EN', 'English → English'),
    };
    return Tooltip(
      message: full,
      excludeFromSemantics: true,
      child: OutlinedButton(
        key: const Key('lookup-mode-toggle'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(44, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: onPressed,
        child: Semantics(
          label: full,
          excludeSemantics: true,
          child: Text(short),
        ),
      ),
    );
  }
}

/// Calls `record` after the result has been shown for
/// [minLookupViewDuration].
///
/// Built only for a finished result, so the timer never runs during loading.
/// Keyed by the event id: a new result (another provider or mode) gets a new
/// timer, and leaving the tree cancels it. Used by words and phrases alike.
class _RecordAfterView extends StatefulWidget {
  const new({required this.record, required this.child, super.key});

  final Future<void> Function() record;
  final Widget child;

  @override
  State<_RecordAfterView> createState() => _RecordAfterViewState();
}

class _RecordAfterViewState extends State<_RecordAfterView> {
  static final Logger _log = Logger('LookupSheet');

  Timer? _timer;
  Animation<double>? _routeAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Closing the sheet starts an exit animation during which the content is
    // still mounted; the result is no longer "on screen" from its start.
    final animation = ModalRoute.of(context)?.animation;
    if (animation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_onRouteStatus);
      animation?.addStatusListener(_onRouteStatus);
      _routeAnimation = animation;
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _timer?.cancel();
    }
  }

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _timer = Timer(minLookupViewDuration, () {
      unawaited(
        record().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            _log.warning('Recording the lookup failed', error, stack);
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ProviderPicker extends StatelessWidget {
  const new({
    required this.providers,
    required this.selected,
    required this.onChanged,
  });

  final List<LookupProvider> providers;
  final ProviderId? selected;
  final ValueChanged<ProviderId?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Dictionary', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(width: 12),
        Flexible(
          child: DropdownButton<ProviderId?>(
            key: const Key('lookup-provider'),
            value: selected,
            isExpanded: true,
            items: [
              const DropdownMenuItem<ProviderId?>(child: Text('Auto')),
              for (final p in providers)
                DropdownMenuItem<ProviderId?>(
                  value: p.id,
                  child: Text(p.info.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
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
        if (transcription != null) ...[
          Text(transcription, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
        ],
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
                if (looksLikeHtml(sense.text))
                  SimpleHtml(sense.text, prefix: '${i + 1}. ')
                else
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

/// Sheet of a phrase (more than one word): translation from the phrase
/// provider only, no mode toggle, no level, no dictionary choice (T-094).
class _PhraseView extends ConsumerWidget {
  const new({required this.query, required this.onOpenSettings});

  final LookupQuery query;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outcome = ref.watch(phraseOutcomeProvider(query));
    void retry() => ref.invalidate(phraseOutcomeProvider(query));
    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            query.text.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          switch (outcome) {
            AsyncLoading() => const _Skeleton(),
            AsyncError() => _Message(
              text: 'Something went wrong.',
              action: TextButton(onPressed: retry, child: const Text('Retry')),
            ),
            AsyncData(:final value) => switch (value) {
              PhraseTranslated() => _RecordAfterView(
                key: ValueKey(value.id),
                record: () async {
                  await ref.read(translatePhraseProvider).record(value);
                },
                child: _PhraseAnswer(outcome: value),
              ),
              PhraseFailed(:final kind) => _PhraseFailure(
                kind: kind,
                onRetry: retry,
                onOpenSettings: onOpenSettings,
              ),
            },
          },
        ],
      ),
    );
  }
}

class _PhraseAnswer extends ConsumerWidget {
  const new({required this.outcome});

  final PhraseTranslated outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(phraseProviderProvider).info.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(outcome.translation, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Text(name, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _PhraseFailure extends StatelessWidget {
  const new({
    required this.kind,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final PhraseFailureKind kind;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final text = switch (kind) {
      PhraseFailureKind.noKey => 'Phrase translation needs a DeepL API key',
      PhraseFailureKind.network =>
        'No connection. Check the network and try again.',
      PhraseFailureKind.timeout => 'DeepL did not answer in time.',
      PhraseFailureKind.badKey =>
        'DeepL rejected the API key. Check it in settings.',
      PhraseFailureKind.quota => 'The DeepL quota of this key is used up.',
      PhraseFailureKind.rateLimit =>
        'Too many requests to DeepL. Wait a moment and try again.',
      PhraseFailureKind.serverError => 'DeepL has a problem. Try again later.',
      PhraseFailureKind.other => 'The translation failed.',
      PhraseFailureKind.notFound => 'No translation for this phrase.',
    };
    final settings = FilledButton(
      onPressed: onOpenSettings,
      child: const Text('Open settings'),
    );
    final retry = TextButton(onPressed: onRetry, child: const Text('Retry'));
    return _Message(
      text: text,
      action: switch (kind) {
        PhraseFailureKind.noKey => settings,
        PhraseFailureKind.badKey => Wrap(
          spacing: 8,
          children: [settings, retry],
        ),
        PhraseFailureKind.notFound => null,
        _ => retry,
      },
    );
  }
}
