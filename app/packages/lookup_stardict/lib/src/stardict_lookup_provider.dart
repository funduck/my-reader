import 'dart:async';
import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';

import 'format/stardict_dict.dart';
import 'format/stardict_idx.dart';
import 'format/stardict_ifo.dart';
import 'stardict_dictionary.dart';

typedef _Opened = ({StarDictIndex index, StarDictDict dict});

/// Offline lookup in one imported StarDict dictionary.
///
/// Serves the single [LookupMode] the dictionary was imported for. The index
/// is loaded on the first lookup and kept in memory with the `.dict` handle
/// until [close]. All entries of the word (homographs) become one [Sense]
/// each; the text is the raw article: plain text, or HTML for `h` articles.
/// A dictionary folder that is missing or unreadable gives
/// [ProviderUnavailable].
class StarDictLookupProvider implements LookupProvider {
  /// Creates a provider for [dictionary].
  new(this.dictionary);

  /// The dictionary this provider reads.
  final StarDictDictionary dictionary;

  Future<_Opened>? _opened;

  @override
  ProviderId get id => dictionary.providerId;

  @override
  ProviderInfo get info => ProviderInfo(
    name: dictionary.name,
    isOnline: false,
    modes: {dictionary.mode},
  );

  @override
  bool supports(LookupMode mode) => mode == dictionary.mode;

  @override
  Future<LookupResult> lookup(LookupQuery query, {CancelToken? cancel}) async {
    cancel?.throwIfCancelled();
    if (!supports(query.mode)) {
      throw ProviderUnavailable(
        '"${dictionary.name}" has no ${query.mode.name}',
      );
    }
    final opened = await _open();
    cancel?.throwIfCancelled();
    final word = query.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final senses = <Sense>[];
    try {
      for (final entry in opened.index.lookup(word)) {
        final text = opened.dict.read(entry).text;
        if (text.isNotEmpty) senses.add(Sense(text: text));
      }
    } on FormatException catch (e) {
      throw ProviderUnavailable('"${dictionary.name}" is damaged: $e');
    } on FileSystemException catch (e) {
      throw ProviderUnavailable('"${dictionary.name}" is unreadable: $e');
    }
    if (senses.isEmpty) throw LookupNotFound('No entry for "${query.text}"');
    return LookupResult(provider: id, senses: senses);
  }

  /// Releases the files; the next lookup reopens them.
  void close() {
    final opened = _opened;
    _opened = null;
    if (opened == null) return;
    unawaited(
      opened.then<void>(
        (o) => o.dict.close(),
        onError: (Object _) {
          // Opening failed, so there is nothing to close.
        },
      ),
    );
  }

  Future<_Opened> _open() async {
    final pending = _opened ??= _load();
    try {
      return await pending;
    } on ProviderUnavailable {
      if (identical(_opened, pending)) _opened = null;
      rethrow;
    }
  }

  Future<_Opened> _load() async {
    final dir = dictionary.directory;
    try {
      final info = StarDictInfo.parse(
        await File('$dir/dict.ifo').readAsString(),
      );
      final index = await StarDictIndex.open('$dir/dict.idx', info);
      final dict = StarDictDict.open('$dir/dict.dict', info);
      return (index: index, dict: dict);
    } on FormatException catch (e) {
      throw ProviderUnavailable('"${dictionary.name}" is damaged: $e');
    } on FileSystemException catch (e) {
      throw ProviderUnavailable('"${dictionary.name}" is not available: $e');
    }
  }
}
