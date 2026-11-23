import 'package:core/ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reader_api/reader_api.dart';

import 'dictionary_library.dart';

/// Thrown when a port is read before `bootstrap.dart` has wired it.
class PortNotWiredError extends StateError {
  /// Creates the error for the port called [port].
  new(String port)
    : super('Port $port is not wired: override its provider in bootstrap.');
}

Provider<T> _port<T>(String name) =>
    Provider<T>((ref) => throw PortNotWiredError(name), name: name);

/// Clock of the app.
final Provider<Clock> clockProvider = _port<Clock>('clockProvider');

/// Generator of identifiers for new entities.
final Provider<IdGenerator> idGeneratorProvider = _port<IdGenerator>(
  'idGeneratorProvider',
);

/// Book library storage.
final Provider<BookRepository> bookRepositoryProvider = _port<BookRepository>(
  'bookRepositoryProvider',
);

/// Reading position storage.
final Provider<ProgressRepository> progressRepositoryProvider =
    _port<ProgressRepository>('progressRepositoryProvider');

/// Journal of lookup events (history).
final Provider<LookupJournal> lookupJournalProvider = _port<LookupJournal>(
  'lookupJournalProvider',
);

/// Journal of translated phrases, separate from lookup events and terms.
final Provider<PhraseJournal> phraseJournalProvider = _port<PhraseJournal>(
  'phraseJournalProvider',
);

/// Storage of terms and their statuses.
final Provider<TermRepository> termRepositoryProvider = _port<TermRepository>(
  'termRepositoryProvider',
);

/// Storage of the user profile.
final Provider<ProfileRepository> profileRepositoryProvider =
    _port<ProfileRepository>('profileRepositoryProvider');

/// Downloadable data packs.
final Provider<PackStore> packStoreProvider = _port<PackStore>(
  'packStoreProvider',
);

/// Sentence and token splitting, lemmatization.
final Provider<TextAnalyzer> textAnalyzerProvider = _port<TextAnalyzer>(
  'textAnalyzerProvider',
);

/// Word levels (CEFR).
final Provider<LevelDictionary> levelDictionaryProvider =
    _port<LevelDictionary>('levelDictionaryProvider');

/// Generator of the pre-reading cheat sheet.
final Provider<CheatSheetGenerator> cheatSheetGeneratorProvider =
    _port<CheatSheetGenerator>('cheatSheetGeneratorProvider');

/// Book format adapters, in the order they are tried.
final Provider<List<BookFormatAdapter>> bookFormatsProvider =
    _port<List<BookFormatAdapter>>('bookFormatsProvider');

/// Lookup providers in registration order.
final Provider<List<LookupProvider>> lookupProvidersProvider =
    _port<List<LookupProvider>>('lookupProvidersProvider');

/// Creates the reader engine that draws books.
final Provider<ReaderEngineFactory> readerEngineFactoryProvider =
    _port<ReaderEngineFactory>('readerEngineFactoryProvider');

/// Secure storage of API keys (DeepL).
final Provider<SecretStore> secretStoreProvider = _port<SecretStore>(
  'secretStoreProvider',
);

/// Library of dictionaries imported by the user (StarDict).
final Provider<DictionaryLibrary> dictionaryLibraryProvider =
    _port<DictionaryLibrary>('dictionaryLibraryProvider');
