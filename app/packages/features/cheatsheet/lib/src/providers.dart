import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;

/// Which cheat sheet to build: the book and where the piece starts.
///
/// A null `from` means the saved reading position (or the book start).
typedef CheatSheetRequest = ({BookId bookId, Locator? from});

/// A built cheat sheet with what the screen needs around it.
class CheatSheetLoad {
  /// Creates the value.
  const new({required this.sheet, required this.scope, required this.mode});

  /// The sheet; null when the book has nothing to analyse from the position.
  final CheatSheet? sheet;

  /// The piece size from the profile, for the title.
  final CheatSheetScope scope;

  /// Lookup direction from the profile, for the queries of tapped words.
  final LookupMode mode;
}

/// Builds the cheat sheet of a [CheatSheetRequest]. Fails with [StateError]
/// when the book is missing or unreadable.
final FutureProviderFamily<CheatSheetLoad, CheatSheetRequest>
cheatSheetProvider = FutureProvider.autoDispose
    .family<CheatSheetLoad, CheatSheetRequest>((ref, request) async {
      final profiles = ref.watch(profileRepositoryProvider);
      final outcome = await OpenBook(
        adapters: ref.watch(bookFormatsProvider),
        books: ref.watch(bookRepositoryProvider),
        progress: ref.watch(progressRepositoryProvider),
      )(request.bookId);
      final BookOpened(:opened, :resumeAt) = switch (outcome) {
        BookOpened() => outcome,
        BookNotFound() => throw StateError('Book ${request.bookId} not found'),
        BookFileUnreadable(:final reason) => throw StateError(reason),
      };
      try {
        final profile = await profiles.get();
        final from =
            request.from ??
            resumeAt ??
            (opened.spine.isEmpty
                ? null
                : Locator(
                    book: request.bookId,
                    chapter: opened.spine.first,
                    progression: 0,
                  ));
        final sheet = from == null
            ? null
            : await BuildCheatSheet(
                generator: ref.watch(cheatSheetGeneratorProvider),
                profiles: profiles,
                terms: ref.watch(termRepositoryProvider),
              )(opened, from: from);
        return CheatSheetLoad(
          sheet: sheet,
          scope: profile.scope,
          mode: profile.mode,
        );
      } finally {
        await opened.close();
      }
    }, retry: (_, _) => null);

/// The first sense of a word for the list, or null when no provider answers.
///
/// Goes through the provider chain only: the lookup is not written to the
/// history, that happens when the user taps the word.
final FutureProviderFamily<String?, ({String text, LookupMode mode})>
itemGlossProvider = FutureProvider.autoDispose
    .family<String?, ({String text, LookupMode mode})>((ref, key) async {
      final cancel = CancelToken();
      ref.onDispose(cancel.cancel);
      final chain = ProviderChain(
        providers: ref.watch(lookupProvidersProvider),
        profiles: ref.watch(profileRepositoryProvider),
      );
      final result = await chain.lookup(
        LookupQuery(text: key.text, mode: key.mode),
        cancel: cancel,
      );
      return switch (result) {
        ChainSuccess(:final result) => result.senses.first.text,
        ChainFailure() => null,
      };
    }, retry: (_, _) => null);
