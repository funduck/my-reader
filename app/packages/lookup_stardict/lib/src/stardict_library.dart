import 'dart:convert';
import 'dart:io';

import 'package:core/domain_lookup.dart';

import 'format/stardict_dict.dart';
import 'format/stardict_idx.dart';
import 'format/stardict_ifo.dart';
import 'stardict_dictionary.dart';
import 'stardict_lookup_provider.dart';

/// StarDict dictionaries imported into one folder of the app.
///
/// Each dictionary lives in `<directory>/<id>/` as `dict.ifo`, `dict.idx`,
/// `dict.dict` (a `.dict.dz` is unpacked at import) and `meta.json`. The
/// metadata file holds the id, title, mode and word count. Imports are not
/// safe against two imports running at once.
class StarDictLibrary {
  /// Creates a library stored in [directory]; created on first import.
  new({required this.directory});

  /// Folder that holds all dictionaries.
  final String directory;

  static const String _ifo = 'dict.ifo';
  static const String _idx = 'dict.idx';
  static const String _dict = 'dict.dict';
  static const String _meta = 'meta.json';
  static const String _tmpPrefix = '.import-';

  /// Imports the dictionary made of [files] and returns it.
  ///
  /// [files] must contain one `.ifo`, one `.idx` and one `.dict` or
  /// `.dict.dz` (`.dict` wins if both are given); other files are ignored.
  /// [mode] is the direction the dictionary serves, [LookupMode.enRu] unless
  /// the user says otherwise. The files are checked and copied into a
  /// temporary folder first, so a failed import leaves nothing behind.
  ///
  /// Throws [FormatException] when a file is missing or malformed and
  /// [FileSystemException] when a file cannot be read or written.
  Future<StarDictDictionary> import(
    List<String> files, {
    LookupMode mode = LookupMode.enRu,
  }) async {
    final ifoPath = _pick(files, ['.ifo'], 'ifo');
    final idxPath = _pick(files, ['.idx'], 'idx');
    final dictPath = _pick(files, ['.dict', '.dict.dz'], 'dict or dict.dz');

    final root = Directory(directory)..createSync(recursive: true);
    final tmp = root.createTempSync(_tmpPrefix);
    try {
      final info = StarDictInfo.parse(await File(ifoPath).readAsString());
      await File(ifoPath).copy('${tmp.path}/$_ifo');
      await File(idxPath).copy('${tmp.path}/$_idx');
      // Parsing checks the size and the word count against the .ifo.
      await StarDictIndex.open('${tmp.path}/$_idx', info);
      if (dictPath.toLowerCase().endsWith('.dz')) {
        await decompressDictDz(dictPath, '${tmp.path}/$_dict');
      } else {
        await File(dictPath).copy('${tmp.path}/$_dict');
      }

      final id = _freshId(info.bookName);
      final dictionary = StarDictDictionary(
        id: id,
        name: info.bookName,
        mode: mode,
        wordCount: info.wordCount,
        directory: '$directory/$id',
      );
      await File('${tmp.path}/$_meta').writeAsString(
        jsonEncode({
          'id': id,
          'name': dictionary.name,
          'mode': mode.toJson(),
          'wordCount': dictionary.wordCount,
        }),
      );
      await tmp.rename(dictionary.directory);
      return dictionary;
    } on Object {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      rethrow;
    }
  }

  /// Lists the imported dictionaries, ordered by name then id.
  ///
  /// Folders without readable metadata (leftovers of a crashed import) are
  /// skipped.
  Future<List<StarDictDictionary>> list() async {
    final root = Directory(directory);
    if (!root.existsSync()) return const [];
    final found = <StarDictDictionary>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final dictionary = _read(entity.path);
      if (dictionary != null) found.add(dictionary);
    }
    found.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return found;
  }

  /// Returns the dictionary with [id], or null if there is none.
  Future<StarDictDictionary?> get(String id) async {
    if (!_validId(id)) return null;
    return _read('$directory/$id');
  }

  /// Deletes the dictionary with [id] and its files; returns whether it
  /// existed. Close its [StarDictLookupProvider] first.
  Future<bool> remove(String id) async {
    if (!_validId(id)) return false;
    final dir = Directory('$directory/$id');
    if (!dir.existsSync()) return false;
    await dir.delete(recursive: true);
    return true;
  }

  /// Builds a provider for [dictionary]. The caller owns it and calls
  /// `close`.
  StarDictLookupProvider providerFor(StarDictDictionary dictionary) =>
      StarDictLookupProvider(dictionary);

  StarDictDictionary? _read(String dir) {
    final file = File('$dir/$_meta');
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?>) return null;
      final id = json['id'];
      final name = json['name'];
      final count = json['wordCount'];
      if (id is! String || name is! String || count is! int) return null;
      if (!dir.endsWith('/$id')) return null;
      return StarDictDictionary(
        id: id,
        name: name,
        mode: LookupMode.fromJson(json['mode'], fallback: LookupMode.enRu),
        wordCount: count,
        directory: dir,
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  String _freshId(String bookName) {
    var base = bookName
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.isEmpty) base = 'dictionary';
    var id = base;
    for (var n = 2; Directory('$directory/$id').existsSync(); n++) {
      id = '$base-$n';
    }
    return id;
  }

  static final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');

  static bool _validId(String id) => _idPattern.hasMatch(id);

  static String _pick(List<String> files, List<String> suffixes, String what) {
    for (final suffix in suffixes) {
      for (final file in files) {
        if (file.toLowerCase().endsWith(suffix)) return file;
      }
    }
    throw FormatException('Missing .$what file in the import set');
  }
}
