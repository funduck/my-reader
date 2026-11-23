import 'dart:io';

import 'package:core/domain_lookup.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('BackgroundTexture');

/// Largest background image that is accepted, in bytes.
const int maxBackgroundBytes = 5 * 1024 * 1024;

/// Ids of the textures bundled in `reader_simple` (`builtInTextures` there).
///
/// Duplicated because a feature does not import a renderer; a test of
/// `reader_simple` checks its own list, the settings test checks this one.
const List<String> builtInTextureIds = ['paper', 'noise', 'linen'];

/// Asset of a bundled texture; the package is `reader_simple`.
String builtInTextureAsset(String id) =>
    'packages/reader_simple/assets/textures/$id.png';

/// Directory where the user's own background images are kept.
///
/// Has no default: `bootstrap.dart` overrides it with a path from the OS. The
/// directory is created on the first write.
final Provider<String> backgroundsDirectoryProvider = Provider<String>(
  (ref) => throw StateError(
    'backgroundsDirectoryProvider is not wired: override it in bootstrap.',
  ),
  name: 'backgroundsDirectoryProvider',
);

/// Asks the user for an image file; returns its path or null when the dialog
/// was cancelled. Tests override it.
final Provider<Future<String?> Function()> backgroundFilePickerProvider =
    Provider<Future<String?> Function()>(
      (ref) => _pickBackgroundFile,
      name: 'backgroundFilePickerProvider',
    );

Future<String?> _pickBackgroundFile() async {
  const images = XTypeGroup(
    label: 'Images',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
  );
  final file = await openFile(
    acceptedTypeGroups: const [images],
    confirmButtonText: 'Choose',
  );
  return file?.path;
}

/// Result of [importBackground].
sealed class BackgroundImport {
  const new();
}

/// The image was copied; [path] is the new file in the backgrounds directory.
final class BackgroundImported extends BackgroundImport {
  /// Creates the result.
  const new(this.path);

  /// Where the copy is.
  final String path;
}

/// The image is larger than [maxBackgroundBytes].
final class BackgroundTooLarge extends BackgroundImport {
  /// Creates the result.
  const new();
}

/// The file could not be read or copied.
final class BackgroundFailed extends BackgroundImport {
  /// Creates the result.
  const new();
}

/// Copies the image at [sourcePath] into [directory] as `<sha256>.<ext>`.
///
/// Nothing is written when the file is larger than [maxBackgroundBytes].
Future<BackgroundImport> importBackground(
  String sourcePath,
  String directory,
) async {
  try {
    final source = File(sourcePath);
    if (await source.length() > maxBackgroundBytes) {
      return const BackgroundTooLarge();
    }
    final bytes = await source.readAsBytes();
    final name = sourcePath.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? 'img' : name.substring(dot + 1).toLowerCase();
    final target = '$directory/${sha256.convert(bytes)}.$extension';
    await Directory(directory).create(recursive: true);
    if (!File(target).existsSync()) await File(target).writeAsBytes(bytes);
    return BackgroundImported(target);
  } on FileSystemException catch (e, s) {
    _log.warning('Cannot import the background image $sourcePath', e, s);
    return const BackgroundFailed();
  }
}

/// Deletes the own image of [old] when [next] no longer uses it.
///
/// Only files inside [directory] are touched.
Future<void> deleteUnusedBackground(
  BackgroundTexture old,
  BackgroundTexture next,
  String directory,
) async {
  if (old is! FileTexture || old == next) return;
  if (!old.path.startsWith('$directory/')) return;
  try {
    final file = File(old.path);
    if (file.existsSync()) await file.delete();
  } on FileSystemException catch (e, s) {
    _log.warning('Cannot delete the old background ${old.path}', e, s);
  }
}
