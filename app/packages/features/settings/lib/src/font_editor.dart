import 'dart:async';

import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import 'font_choice.dart';

final Logger _log = Logger('FontEditor');

/// The "Font" row of the reading section: a button that picks a folder (or,
/// on Android, font files), a list of the fonts found and a sample paragraph.
class FontEditor extends ConsumerStatefulWidget {
  /// Creates the editor for the current [display] preferences.
  const new({required this.display, super.key});

  /// Current display preferences.
  final DisplayPrefs display;

  @override
  ConsumerState<FontEditor> createState() => _FontEditorState();
}

class _FontEditorState extends ConsumerState<FontEditor> {
  List<FontEntry> _entries = const [];
  bool _scanned = false;
  String? _error;

  /// Family of the font that is registered with the engine and can be drawn.
  String? _readyFamily;

  @override
  void initState() {
    super.initState();
    final folder = widget.display.fontFolder;
    if (folder != null && !ref.read(fontPickByFilesProvider)) {
      unawaited(_scan(folder));
    }
    _prepare(widget.display.font);
  }

  @override
  void didUpdateWidget(FontEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.display.font != widget.display.font) {
      _prepare(widget.display.font);
    }
  }

  void _prepare(FontChoice? font) {
    if (font == null) return;
    unawaited(
      loadUserFont(font).then((ok) {
        if (mounted && ok) setState(() => _readyFamily = font.family);
      }),
    );
  }

  Future<void> _scan(String folder) async {
    final found = await findFonts(folder);
    if (!mounted) return;
    setState(() {
      _entries = found;
      _scanned = true;
    });
  }

  Future<void> _pickSource() async {
    if (ref.read(fontPickByFilesProvider)) {
      final paths = await ref.read(fontFilesPickerProvider)();
      if (paths.isEmpty || !mounted) return;
      final found = await fontsFromFiles(paths);
      if (!mounted) return;
      setState(() {
        _entries = found;
        _scanned = true;
        _error = null;
      });
      return;
    }
    final folder = await ref.read(fontFolderPickerProvider)();
    if (folder == null || !mounted) return;
    await _update((d) => d.copyWith(fontFolder: () => folder));
    await _scan(folder);
  }

  Future<void> _update(DisplayPrefs Function(DisplayPrefs) change) async {
    final repository = ref.read(profileRepositoryProvider);
    try {
      final profile = await repository.get();
      await repository.save(profile.copyWith(display: change(profile.display)));
    } on Exception catch (e, s) {
      _log.warning('Cannot save the font', e, s);
    }
  }

  /// Chooses the font [family] of the list, or the system font for null.
  Future<void> _choose(String? family) async {
    final directory = ref.read(fontsDirectoryProvider);
    final old = widget.display.font;
    FontChoice? next;
    if (family == null) {
      _log.info('Font chosen: system');
    } else {
      final entry = _entries.where((e) => e.name == family).firstOrNull;
      if (entry == null) return; // the current font, already chosen
      final copy = await importFont(entry.path, directory);
      if (!mounted) return;
      if (copy == null) {
        setState(() => _error = 'Cannot read the font file. Choose another.');
        return;
      }
      _log.info('Font chosen: $family (${entry.path})');
      next = FontChoice(path: copy, family: family);
    }
    setState(() => _error = null);
    await _update((d) => d.copyWith(font: () => next));
    if (old != null && old.path != next?.path) {
      await deleteFontCopy(old.path, directory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final font = widget.display.font;
    final byFiles = ref.watch(fontPickByFilesProvider);
    final names = [
      for (final e in _entries) e.name,
      if (font != null && !_entries.any((e) => e.name == font.family))
        font.family,
    ];
    final folder = widget.display.fontFolder;
    final needsFolder =
        !byFiles && folder != null && _scanned && _entries.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Шрифт', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButton<String?>(
                key: const Key('font-select'),
                isExpanded: true,
                value: font?.family,
                items: [
                  const DropdownMenuItem<String?>(child: Text('Системный')),
                  for (final name in names)
                    DropdownMenuItem<String?>(value: name, child: Text(name)),
                ],
                onChanged: (v) => unawaited(_choose(v)),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              key: const Key('font-pick'),
              onPressed: () => unawaited(_pickSource()),
              child: Text(byFiles ? 'Файлы шрифтов…' : 'Папка со шрифтами…'),
            ),
          ],
        ),
        if (needsFolder)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              key: const Key('font-folder-hint'),
              'Выбери папку ещё раз',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              key: const Key('font-error'),
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          key: const Key('font-sample'),
          'The quick brown fox jumps over the lazy dog. '
          'Reading in your own language of colours is easier on the eyes.',
          style: TextStyle(
            fontFamily: font != null && _readyFamily == font.family
                ? font.family
                : null,
            fontSize: widget.display.fontSize,
            height: widget.display.lineHeight,
          ),
        ),
      ],
    );
  }
}
