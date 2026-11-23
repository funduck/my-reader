import 'dart:async';
import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:features_common/features_common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('DictionariesController');

/// Asks the user for the files of one StarDict dictionary (`.ifo`, `.idx`,
/// `.dict` or `.dict.dz`) and returns their paths; empty when cancelled.
///
/// A port of its own so that tests do not open a system dialog.
///
/// `file_picker`, not `file_selector`: on Android both copy the picked files
/// into the cache, but `file_selector` replaces the extension with one
/// guessed from the MIME type, and `.ifo`/`.idx`/`.dict.dz` have none, so
/// the import could not tell the files apart. `file_picker` keeps the name.
final Provider<Future<List<String>> Function()> dictionaryFilePickerProvider =
    Provider<Future<List<String>> Function()>((ref) => _pickDictionaryFiles);

Future<List<String>> _pickDictionaryFiles() async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'Choose the dictionary files',
    allowMultiple: true,
  );
  return [
    for (final file in result?.files ?? const <PlatformFile>[]) ?file.path,
  ];
}

/// State of the dictionaries section.
@immutable
class DictionariesState {
  /// Creates a state.
  const new({
    this.dictionaries = const [],
    this.loading = true,
    this.busy = false,
    this.error,
  });

  /// Imported dictionaries.
  final List<ImportedDictionary> dictionaries;

  /// Whether the list is being read.
  final bool loading;

  /// Whether an import or a removal is running.
  final bool busy;

  /// Message of the last failure.
  final String? error;

  /// Copy with some fields replaced; [error] can be cleared.
  DictionariesState copyWith({
    List<ImportedDictionary>? dictionaries,
    bool? loading,
    bool? busy,
    String? Function()? error,
  }) => DictionariesState(
    dictionaries: dictionaries ?? this.dictionaries,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: error != null ? error() : this.error,
  );
}

/// Lists, imports and removes the user's dictionaries.
class DictionariesController extends Notifier<DictionariesState> {
  @override
  DictionariesState build() {
    ref.watch(dictionaryLibraryProvider);
    unawaited(Future<void>.microtask(refresh));
    return const DictionariesState();
  }

  /// Reads the list of dictionaries again.
  Future<void> refresh() async {
    try {
      final list = await ref.read(dictionaryLibraryProvider).list();
      if (!ref.mounted) return;
      state = state.copyWith(dictionaries: list, loading: false);
    } on Exception catch (e, s) {
      _log.warning('Cannot list dictionaries', e, s);
      if (!ref.mounted) return;
      state = state.copyWith(
        loading: false,
        error: () => 'Cannot read dictionaries: $e',
      );
    }
  }

  /// Imports the dictionary made of [files] for [mode].
  ///
  /// Returns whether it succeeded; a failure goes to [DictionariesState.error].
  Future<bool> import(List<String> files, LookupMode mode) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, error: () => null);
    try {
      final dictionary = await ref
          .read(dictionaryLibraryProvider)
          .import(files, mode);
      _log.info('Imported dictionary ${dictionary.id}');
      await refresh();
      if (ref.mounted) state = state.copyWith(busy: false);
      return true;
    } on FormatException catch (e) {
      _log.warning('Bad dictionary files', e);
      _fail('Not a StarDict dictionary: ${e.message}');
    } on FileSystemException catch (e, s) {
      _log.warning('Cannot read dictionary files', e, s);
      _fail('Cannot read the files: ${e.message}');
    }
    return false;
  }

  /// Deletes the dictionary [id] and forgets it in the provider order.
  Future<void> remove(String id) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, error: () => null);
    try {
      final library = ref.read(dictionaryLibraryProvider);
      final dictionary = [
        for (final d in state.dictionaries)
          if (d.id == id) d,
      ];
      await library.remove(id);
      if (dictionary.isNotEmpty) {
        final repository = ref.read(profileRepositoryProvider);
        final profile = await repository.get();
        final gone = dictionary.first.providerId;
        if (profile.providerOrder.contains(gone)) {
          await repository.save(
            profile.copyWith(
              providerOrder: [
                for (final p in profile.providerOrder)
                  if (p != gone) p,
              ],
            ),
          );
        }
      }
      await refresh();
      if (ref.mounted) state = state.copyWith(busy: false);
    } on Exception catch (e, s) {
      _log.warning('Cannot remove dictionary $id', e, s);
      _fail('Cannot remove: $e');
    }
  }

  void _fail(String message) {
    if (ref.mounted) state = state.copyWith(busy: false, error: () => message);
  }
}

/// Provider of [DictionariesController].
final NotifierProvider<DictionariesController, DictionariesState>
dictionariesControllerProvider =
    NotifierProvider<DictionariesController, DictionariesState>(
      DictionariesController.new,
    );
