import 'dart:async';

import 'package:core/application.dart';
import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

/// Status of the term with the key `termKey`, `null` while the word has no
/// term. Follows the repository, so a mark made anywhere shows at once.
final StreamProviderFamily<TermStatus?, String> termStatusProvider =
    StreamProvider.autoDispose.family<TermStatus?, String>(
      (ref, key) => ref
          .watch(termRepositoryProvider)
          .watchAll()
          .map(
            (terms) => [
              for (final t in terms)
                if (t.normalized == key && t.language == lookupLanguage)
                  t.status,
            ].firstOrNull,
          ),
      name: 'termStatusProvider',
    );

/// The "Знаю" switch of the sheet header (T-098): marks the word known, a
/// second tap makes it `learning` again.
///
/// Works on the term the lookups of the word write to, so it can be used
/// before the lookup is recorded: the mark then creates a term with no
/// lookups, and a later `record` counts into it.
class KnownToggle extends ConsumerWidget {
  /// Creates the switch for the single word [text].
  const new({required this.text, super.key});

  /// The looked-up word as selected.
  final String text;

  static final Logger _log = Logger('KnownToggle');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = termKey(ref.watch(textAnalyzerProvider), text);
    final known = ref.watch(termStatusProvider(key)).value == TermStatus.known;
    return FilterChip(
      key: const Key('lookup-known-toggle'),
      label: const Text('Знаю'),
      selected: known,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => unawaited(
        ref
            .read(setTermStatusProvider)(
              key,
              known ? TermStatus.learning : TermStatus.known,
            )
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                _log.warning('Marking "$key" failed', error, stack);
              },
            ),
      ),
    );
  }
}
