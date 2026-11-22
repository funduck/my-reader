import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:meta/meta.dart';

/// An imported StarDict dictionary as the `StarDictLibrary` stores it.
@immutable
class StarDictDictionary {
  /// Creates the description of a dictionary stored in [directory].
  const new({
    required this.id,
    required this.name,
    required this.mode,
    required this.wordCount,
    required this.directory,
  });

  /// Stable id, also the name of the dictionary's folder in the library.
  final String id;

  /// Title from the `.ifo` (`bookname`).
  final String name;

  /// Direction the user chose at import.
  final LookupMode mode;

  /// Number of headwords in the index.
  final int wordCount;

  /// Absolute path of the folder with the dictionary's files.
  final String directory;

  /// Id of the [LookupProvider] built for this dictionary, stored in history.
  ProviderId get providerId => ProviderId('stardict.$id');

  @override
  bool operator ==(Object other) =>
      other is StarDictDictionary &&
      other.id == id &&
      other.name == name &&
      other.mode == mode &&
      other.wordCount == wordCount &&
      other.directory == directory;

  @override
  int get hashCode => Object.hash(id, name, mode, wordCount, directory);

  @override
  String toString() => 'StarDictDictionary($id, $name, ${mode.name})';
}
