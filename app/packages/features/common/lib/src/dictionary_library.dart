import 'package:core/domain_lookup.dart';

/// A dictionary imported by the user, as settings show it.
final class ImportedDictionary {
  /// Creates the description of a dictionary.
  const new({
    required this.id,
    required this.name,
    required this.mode,
    required this.wordCount,
    required this.providerId,
  });

  /// Stable id of the dictionary in the library.
  final String id;

  /// Title of the dictionary.
  final String name;

  /// Direction the dictionary serves.
  final LookupMode mode;

  /// Number of headwords.
  final int wordCount;

  /// Id of the lookup provider that reads this dictionary.
  final ProviderId providerId;
}

/// Library of dictionaries the user imports (StarDict).
///
/// A change (import, removal) rebuilds `lookupProvidersProvider`; features
/// only call this port and read the providers again.
abstract interface class DictionaryLibrary {
  /// Lists the imported dictionaries, ordered by name.
  Future<List<ImportedDictionary>> list();

  /// Imports the dictionary made of the files at [files] for [mode].
  ///
  /// Throws [FormatException] when a file is missing or malformed and
  /// `FileSystemException` when a file cannot be read.
  Future<ImportedDictionary> import(List<String> files, LookupMode mode);

  /// Deletes the dictionary [id]; returns whether it existed.
  Future<bool> remove(String id);
}
