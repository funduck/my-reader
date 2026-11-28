import 'dart:async';

import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

final Logger _log = Logger('TranslationSection');

/// Page where a free DeepL API key is issued.
const deeplKeyHelpUrl = 'https://www.deepl.com/pro-api';

/// The DeepL API key from the secret store, `null` if none is saved.
final FutureProvider<String?> deeplKeyProvider =
    FutureProvider.autoDispose<String?>(
      (ref) => ref.watch(secretStoreProvider).read(deeplApiKey),
    );

/// What the screen shows of [key]: dots and at most the last four characters.
///
/// A key of four characters or fewer is hidden entirely.
String maskedKey(String key) {
  const dots = '••••';
  return key.length > 4 ? '$dots${key.substring(key.length - 4)}' : dots;
}

/// The "Translation" section: the DeepL API key.
///
/// The key lives only in the `SecretStore`; it is never logged and never put
/// in the profile. Once saved, the screen shows only its last four characters.
class TranslationSection extends ConsumerStatefulWidget {
  /// Creates the section.
  const new({super.key});

  @override
  ConsumerState<TranslationSection> createState() => _TranslationSectionState();
}

class _TranslationSectionState extends ConsumerState<TranslationSection> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Enter the key');
      return;
    }
    await _write(key, failure: 'Cannot save the key');
  }

  Future<void> _remove() => _write(null, failure: 'Cannot remove the key');

  Future<void> _write(String? key, {required String failure}) async {
    final store = ref.read(secretStoreProvider);
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await store.write(deeplApiKey, key);
      _controller.clear();
      ref.invalidate(deeplKeyProvider);
    } on Exception catch (e, s) {
      // Only the failure is logged, never the key.
      _log.warning(failure, e, s);
      if (mounted) setState(() => _error = '$failure: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = ref.watch(deeplKeyProvider);
    final savedKey = saved.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Translation', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'DeepL API key, used to translate phrases.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (saved.hasError)
          Text(
            'Cannot read the saved key.',
            style: TextStyle(color: theme.colorScheme.error),
          )
        else if (savedKey != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: InfoLabel(
              child: Text(
                'Saved key: ${maskedKey(savedKey)}',
                key: const Key('deepl-key-saved'),
              ),
            ),
          )
        else if (saved.hasValue)
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: InfoLabel(
              child: Text('No key saved', key: Key('deepl-key-none')),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('deepl-key'),
                controller: _controller,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_save()),
                decoration: InputDecoration(
                  labelText: 'DeepL API key',
                  errorText: _error,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton(
                key: const Key('deepl-save'),
                onPressed: _busy ? null : () => unawaited(_save()),
                child: const Text('Save'),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                key: const Key('deepl-remove'),
                onPressed: _busy || savedKey == null
                    ? null
                    : () => unawaited(_remove()),
                child: const Text('Remove'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const SelectableText(
          'Get a free key: $deeplKeyHelpUrl',
          key: Key('deepl-key-help'),
        ),
      ],
    );
  }
}
