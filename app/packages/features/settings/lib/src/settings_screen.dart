import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import 'packs_controller.dart';

final Logger _log = Logger('SettingsScreen');

/// Address of the service used when none is configured.
const defaultServiceUrl = 'http://localhost:8080';

/// Page counts offered for the cheat sheet piece.
const _pageChoices = [1, 2, 3, 5, 10, 15, 20, 30];

/// Profile from storage, updated on every change.
final StreamProvider<UserProfile> profileProvider = StreamProvider<UserProfile>(
  (ref) => ref.watch(profileRepositoryProvider).watch(),
);

/// Whether [text] is an http(s) address with a host.
bool isValidServiceUrl(String text) {
  final uri = Uri.tryParse(text);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Settings: service address, mode, level, cheat sheet size and packs.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Cannot load the profile: $e')),
        data: (p) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ServiceUrlField(initial: p.serviceUrl),
            const SizedBox(height: 24),
            _ModeSetting(profile: p),
            const SizedBox(height: 24),
            _LevelSetting(profile: p),
            const SizedBox(height: 24),
            _ScopeSetting(profile: p),
            const SizedBox(height: 24),
            const PacksSection(),
          ],
        ),
      ),
    );
  }
}

Future<void> _update(
  WidgetRef ref,
  UserProfile Function(UserProfile) change,
) async {
  final repository = ref.read(profileRepositoryProvider);
  await repository.save(change(await repository.get()));
}

class _ServiceUrlField extends ConsumerStatefulWidget {
  const new({required this.initial});

  final String? initial;

  @override
  ConsumerState<_ServiceUrlField> createState() => _ServiceUrlFieldState();
}

class _ServiceUrlFieldState extends ConsumerState<_ServiceUrlField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !isValidServiceUrl(text)) {
      setState(() => _error = 'Enter an http:// or https:// address');
      return;
    }
    setState(() => _error = null);
    try {
      await _update(
        ref,
        (p) => p.copyWith(serviceUrl: () => text.isEmpty ? null : text),
      );
    } on Exception catch (e, s) {
      _log.warning('Cannot save the service address', e, s);
      if (mounted) setState(() => _error = 'Cannot save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_save()),
            decoration: InputDecoration(
              labelText: 'Service address',
              hintText: defaultServiceUrl,
              errorText: _error,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton(
            onPressed: () => unawaited(_save()),
            child: const Text('Save address'),
          ),
        ),
      ],
    );
  }
}

class _ModeSetting extends ConsumerWidget {
  const new({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Labeled(
      label: 'Default lookup mode',
      child: SegmentedButton<LookupMode>(
        segments: const [
          ButtonSegment(value: LookupMode.enRu, label: Text('EN → RU')),
          ButtonSegment(value: LookupMode.enEn, label: Text('EN → EN')),
        ],
        selected: {profile.mode},
        onSelectionChanged: (s) =>
            unawaited(_update(ref, (p) => p.copyWith(mode: s.first))),
      ),
    );
  }
}

class _LevelSetting extends ConsumerWidget {
  const new({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Labeled(
      label: 'My level',
      child: DropdownButton<CefrLevel>(
        key: const Key('level'),
        value: profile.level,
        items: [
          for (final level in CefrLevel.values)
            if (level.isKnown)
              DropdownMenuItem(
                value: level,
                child: Text(level.name.toUpperCase()),
              ),
        ],
        onChanged: (level) {
          if (level != null) {
            unawaited(_update(ref, (p) => p.copyWith(level: level)));
          }
        },
      ),
    );
  }
}

class _ScopeSetting extends ConsumerWidget {
  const new({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = profile.scope;
    final pages = scope is CheatSheetPages ? scope.pages : null;
    final choices = {..._pageChoices, ?pages}.toList()..sort();
    return _Labeled(
      label: 'Cheat sheet piece',
      child: Row(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Pages')),
              ButtonSegment(value: false, label: Text('To end of chapter')),
            ],
            selected: {pages != null},
            onSelectionChanged: (s) => unawaited(
              _update(
                ref,
                (p) => p.copyWith(
                  scope: s.first
                      ? CheatSheetScope.defaultScope
                      : const CheatSheetChapter(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (pages != null)
            DropdownButton<int>(
              key: const Key('pages'),
              value: pages,
              items: [
                for (final n in choices)
                  DropdownMenuItem(value: n, child: Text('$n')),
              ],
              onChanged: (n) {
                if (n != null) {
                  unawaited(
                    _update(ref, (p) => p.copyWith(scope: CheatSheetPages(n))),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const new({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// The "Packs" section: manifest, status and download buttons.
class PacksSection extends ConsumerWidget {
  /// Creates the section.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(packsControllerProvider);
    final controller = ref.read(packsControllerProvider.notifier);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Packs', style: theme.textTheme.titleMedium)),
            IconButton(
              tooltip: 'Refresh packs',
              onPressed: state.loading
                  ? null
                  : () => unawaited(controller.refresh()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (state.loading) const LinearProgressIndicator(),
        if (state.manifestError case final message?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        for (final row in state.rows)
          _PackTile(
            row: row,
            onDownload: () => unawaited(controller.download(row.id)),
          ),
      ],
    );
  }
}

class _PackTile extends StatelessWidget {
  const new({required this.row, required this.onDownload});

  final PackRow row;
  final VoidCallback onDownload;

  String get _statusText => switch (row.status) {
    PackStatus.available => 'Not installed',
    PackStatus.installed => 'Installed ${row.installedVersion}',
    PackStatus.updatable =>
      'Installed ${row.installedVersion}, update ${row.offered?.version}',
    PackStatus.downloading =>
      'Downloading ${((row.progress ?? 0) * 100).round()}%',
  };

  @override
  Widget build(BuildContext context) {
    final size = row.offered?.sizeBytes;
    final error = row.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(row.id),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([_statusText, ?(size == null ? null : _mb(size))].join(' · ')),
          if (row.status == PackStatus.downloading)
            LinearProgressIndicator(value: row.progress),
          if (error != null)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      trailing: switch (row.status) {
        PackStatus.downloading => null,
        PackStatus.installed => const Icon(Icons.check),
        PackStatus.available || PackStatus.updatable => FilledButton(
          onPressed: row.offered == null ? null : onDownload,
          child: Text(
            row.status == PackStatus.updatable ? 'Update' : 'Download',
          ),
        ),
      },
    );
  }
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
