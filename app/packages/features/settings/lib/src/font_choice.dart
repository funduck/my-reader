import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:features_common/features_common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('FontChoice');

/// Extensions of the font files that are listed; `.ttc` is skipped because
/// `FontLoader` cannot load collections.
const List<String> fontExtensions = ['ttf', 'otf'];

/// Directory where copies of the chosen fonts are kept.
///
/// Has no default: `bootstrap.dart` overrides it with a path from the OS
/// (`<applicationSupport>/fonts`). Created on the first write.
final Provider<String> fontsDirectoryProvider = Provider<String>(
  (ref) => throw StateError(
    'fontsDirectoryProvider is not wired: override it in bootstrap.',
  ),
  name: 'fontsDirectoryProvider',
);

/// Whether fonts are chosen as files instead of a folder (Android, where the
/// folder dialog gives a SAF URI that `dart:io` cannot read).
final Provider<bool> fontPickByFilesProvider = Provider<bool>(
  (ref) => Platform.isAndroid,
  name: 'fontPickByFilesProvider',
);

/// Asks for a folder; returns its path or null when cancelled. Tests override
/// it.
final Provider<Future<String?> Function()> fontFolderPickerProvider =
    Provider<Future<String?> Function()>(
      (ref) =>
          () => getDirectoryPath(confirmButtonText: 'Choose'),
      name: 'fontFolderPickerProvider',
    );

/// Asks for font files; returns their paths, empty when cancelled. Tests
/// override it.
final Provider<Future<List<String>> Function()> fontFilesPickerProvider =
    Provider<Future<List<String>> Function()>(
      (ref) => _pickFontFiles,
      name: 'fontFilesPickerProvider',
    );

Future<List<String>> _pickFontFiles() async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: true);
  if (result == null) return const [];
  return [
    for (final file in result.files)
      if (file.path != null) file.path!,
  ];
}

/// A font file found by the search.
final class FontEntry {
  /// Creates an entry for the file at [path] shown as [name].
  const new({required this.path, required this.name});

  /// Path of the file.
  final String path;

  /// `Family Style` from the `name` table, or the file name.
  final String name;
}

String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

String _extension(String path) {
  final name = _baseName(path);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// The `.ttf` and `.otf` files in [folder] and its subfolders, as a sorted
/// list without duplicate names.
///
/// A folder that cannot be read gives an empty list; unreadable subfolders
/// are skipped.
Future<List<FontEntry>> findFonts(String folder) async {
  final files = <String>[];
  Future<void> walk(Directory directory) async {
    final List<FileSystemEntity> children;
    try {
      children = await directory.list(followLinks: false).toList();
    } on FileSystemException catch (e, s) {
      _log.warning('Cannot read the font folder ${directory.path}', e, s);
      return;
    }
    for (final child in children) {
      if (child is Directory) {
        await walk(child);
      } else if (child is File &&
          fontExtensions.contains(_extension(child.path))) {
        files.add(child.path);
      }
    }
  }

  await walk(Directory(folder));
  return await fontsFromFiles(files);
}

/// Entries for the font [paths] chosen one by one; files that are not
/// `.ttf`/`.otf` are dropped. Sorted by name, duplicates removed.
Future<List<FontEntry>> fontsFromFiles(List<String> paths) async {
  final sorted = [
    for (final path in paths)
      if (fontExtensions.contains(_extension(path))) path,
  ]..sort();
  final byName = <String, FontEntry>{};
  for (final path in sorted) {
    final name = (await readFontNameFromFile(path))?.display ?? _baseName(path);
    byName.putIfAbsent(name, () => FontEntry(path: path, name: name));
  }
  return byName.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Copies the font at [sourcePath] into [directory] as `<sha256>.<ext>`.
///
/// Returns the copy, or null when the file cannot be read or written.
Future<String?> importFont(String sourcePath, String directory) async {
  try {
    final bytes = await File(sourcePath).readAsBytes();
    final target =
        '$directory/${sha256.convert(bytes)}.${_extension(sourcePath)}';
    await Directory(directory).create(recursive: true);
    if (!File(target).existsSync()) await File(target).writeAsBytes(bytes);
    return target;
  } on FileSystemException catch (e, s) {
    _log.warning('Cannot import the font $sourcePath', e, s);
    return null;
  }
}

/// Deletes the copy at [path] when it lies in [directory].
Future<void> deleteFontCopy(String path, String directory) async {
  if (!path.startsWith('$directory/')) return;
  try {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  } on FileSystemException catch (e, s) {
    _log.warning('Cannot delete the old font $path', e, s);
  }
}
