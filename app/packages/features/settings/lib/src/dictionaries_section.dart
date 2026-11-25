import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import 'dictionaries_controller.dart';

final Logger _log = Logger('DictionariesSection');

/// Providers in the order the lookup chain tries them: the ids of [order]
/// first, in that order, then the rest in registration order.
List<LookupProvider> orderedProviders(
  List<LookupProvider> providers,
  List<ProviderId> order,
) {
  final result = <LookupProvider>[];
  for (final id in order) {
    for (final p in providers) {
      if (p.id == id && !result.contains(p)) result.add(p);
    }
  }
  for (final p in providers) {
    if (!result.contains(p)) result.add(p);
  }
  return result;
}

String _modeName(LookupMode mode) => switch (mode) {
  LookupMode.enRu => 'EN → RU',
  LookupMode.enEn => 'EN → EN',
};

/// The "Dictionaries" section: imported StarDict dictionaries, import and
/// removal.
class DictionariesSection extends ConsumerWidget {
  /// Creates the section.
  const new({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(dictionariesControllerProvider.notifier);
    final List<String> files;
    try {
      files = await ref.read(dictionaryFilePickerProvider)();
    } on Exception catch (e, s) {
      _log.warning('The file dialog failed', e, s);
      return;
    }
    if (files.isEmpty || !context.mounted) return;
    final mode = await showDialog<LookupMode>(
      context: context,
      builder: (_) => const _ModeDialog(),
    );
    if (mode == null) return;
    await controller.import(files, mode);
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ImportedDictionary dictionary,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${dictionary.name}"?'),
        content: const Text(
          'The imported copy is deleted; the original files stay where they '
          'are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(dictionariesControllerProvider.notifier)
        .remove(dictionary.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dictionariesControllerProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Dictionaries', style: theme.textTheme.titleMedium),
            ),
            FilledButton.icon(
              key: const Key('import-dictionary'),
              onPressed: state.busy
                  ? null
                  : () => unawaited(_import(context, ref)),
              icon: const Icon(Icons.file_open),
              label: const Text('Import StarDict'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Pick the .ifo, .idx and .dict (or .dict.dz) files together.',
          style: theme.textTheme.bodySmall,
        ),
        if (state.loading || state.busy) const LinearProgressIndicator(),
        if (state.error case final message?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (!state.loading && state.dictionaries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No dictionaries imported.'),
          ),
        for (final d in state.dictionaries)
          ListTile(
            key: Key('dictionary-${d.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(d.name),
            subtitle: Text('${_modeName(d.mode)} · ${d.wordCount} words'),
            trailing: IconButton(
              tooltip: 'Delete ${d.name}',
              onPressed: state.busy
                  ? null
                  : () => unawaited(_remove(context, ref, d)),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
      ],
    );
  }
}

class _ModeDialog extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Which direction does it translate?'),
      children: [
        for (final mode in [LookupMode.enRu, LookupMode.enEn])
          SimpleDialogOption(
            key: Key('mode-${mode.name}'),
            onPressed: () => Navigator.of(context).pop(mode),
            child: Text(_modeName(mode)),
          ),
      ],
    );
  }
}

/// The "Lookup order" section: providers in the order they are tried,
/// changed by dragging.
class ProviderOrderSection extends ConsumerWidget {
  /// Creates the section.
  const new({required this.order, super.key});

  /// `UserProfile.providerOrder`.
  final List<ProviderId> order;

  Future<void> _move(
    WidgetRef ref,
    List<LookupProvider> current,
    int from,
    int to,
  ) async {
    final ids = [for (final p in current) p.id];
    ids.insert(to, ids.removeAt(from));
    try {
      final repository = ref.read(profileRepositoryProvider);
      await repository.update(
        (profile) => profile.copyWith(providerOrder: ids),
      );
    } on Exception catch (e, s) {
      _log.warning('Cannot save the provider order', e, s);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = orderedProviders(
      ref.watch(lookupProvidersProvider),
      order,
    );
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lookup order', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Dictionaries are tried from the top until one has the word. '
          'Drag to reorder.',
          style: theme.textTheme.bodySmall,
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) =>
              unawaited(_move(ref, providers, from, to)),
          children: [
            for (final (i, p) in providers.indexed)
              ListTile(
                key: Key('order-${p.id.value}'),
                contentPadding: EdgeInsets.zero,
                title: Text(p.info.name),
                subtitle: Text(
                  [
                    for (final m in LookupMode.values)
                      if (p.info.modes.contains(m)) _modeName(m),
                    if (p.info.isOnline) 'online' else 'offline',
                  ].join(' · '),
                ),
                trailing: ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_handle),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
