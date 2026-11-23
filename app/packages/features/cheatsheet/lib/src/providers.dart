import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, NotifierProviderFamily, ProviderFamily;
import 'package:logging/logging.dart';

/// Which cheat sheet to build: the book and where the piece starts.
///
/// A null `from` means the saved reading position (or the book start).
typedef CheatSheetRequest = ({BookId bookId, Locator? from});

/// A built cheat sheet with what the screen needs around it.
///
/// [sheet] holds every candidate the generator found, not the part shown.
class CheatSheetLoad {
  /// Creates the value.
  const new({required this.sheet, required this.scope, required this.mode});

  /// The sheet with all candidates; null when the book has nothing to analyse
  /// from the position.
  final CheatSheet? sheet;

  /// The piece size from the profile, for the title.
  final CheatSheetScope scope;

  /// Lookup direction from the profile, for the queries of tapped words.
  final LookupMode mode;
}

/// Builds the cheat sheet of a [CheatSheetRequest] once: opens the book, runs
/// the generator. Fails with [StateError] when the book is missing or
/// unreadable.
///
/// Does not watch the profile: the level, the limit and the "known" marks
/// change what is shown (`cheatSheetItemsProvider`), not the sheet.
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
        // The whole list of candidates: level, limit and "known" are applied
        // by `cheatSheetItemsProvider`, so changing them never lands here.
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

/// The profile with the level and the limit of the sheet; follows the
/// repository, so a change made here or in the settings shows at once.
final StreamProvider<UserProfile> cheatSheetProfileProvider =
    StreamProvider.autoDispose<UserProfile>(
      (ref) => ref.watch(profileRepositoryProvider).watch(),
      name: 'cheatSheetProfileProvider',
    );

/// The words marked "Знаю" on the screen of a [CheatSheetRequest], by
/// `CheatSheetItem.text`; the selection leaves them out.
///
/// Marks done in this visit only: a sheet built later hides the known terms
/// itself (`BuildCheatSheet`).
final NotifierProviderFamily<CheatSheetKnown, Set<String>, CheatSheetRequest>
cheatSheetKnownProvider = NotifierProvider.autoDispose
    .family<CheatSheetKnown, Set<String>, CheatSheetRequest>(
      CheatSheetKnown.new,
      name: 'cheatSheetKnownProvider',
    );

/// The marks of "Знаю" and "Undo" of one cheat sheet screen.
class CheatSheetKnown extends Notifier<Set<String>> {
  /// Creates the notifier of [request].
  new(this.request);

  /// The sheet this notifier belongs to.
  final CheatSheetRequest request;

  static final Logger _log = Logger('CheatSheetKnown');

  @override
  Set<String> build() => const {};

  /// Hides [item] at once and marks its term `known`.
  ///
  /// The term is the one lookups of the word write to (`termKey`). When the
  /// write fails, the item comes back and the error is logged.
  Future<void> markKnown(CheatSheetItem item) =>
      _mark(item, TermStatus.known, hidden: true);

  /// Shows [item] again and puts its term back to `learning`.
  Future<void> undo(CheatSheetItem item) =>
      _mark(item, TermStatus.learning, hidden: false);

  Future<void> _mark(
    CheatSheetItem item,
    TermStatus status, {
    required bool hidden,
  }) async {
    final setStatus = ref.read(setTermStatusProvider);
    final key = termKey(ref.read(textAnalyzerProvider), item.text);
    state = _with(item.text, hidden: hidden);
    try {
      await setStatus(key, status);
    } on Object catch (error, stack) {
      _log.warning('Marking "$key" as ${status.name} failed', error, stack);
      if (ref.mounted) state = _with(item.text, hidden: !hidden);
    }
  }

  Set<String> _with(String text, {required bool hidden}) =>
      hidden ? {...state, text} : ({...state}..remove(text));
}

/// The rows to show: the candidates of the sheet cut by the level and the
/// limit of the profile, without the words marked known on the screen.
///
/// A cheap function over the built sheet (`selectCheatSheetItems`): a change
/// of the level, the limit or a mark recomputes it and nothing else.
final ProviderFamily<AsyncValue<List<CheatSheetItem>>, CheatSheetRequest>
cheatSheetItemsProvider = Provider.autoDispose
    .family<AsyncValue<List<CheatSheetItem>>, CheatSheetRequest>((
      ref,
      request,
    ) {
      final load = ref.watch(cheatSheetProvider(request));
      final profile = ref.watch(cheatSheetProfileProvider);
      final hidden = ref.watch(cheatSheetKnownProvider(request));
      if (load case AsyncData(:final value) when profile.hasValue) {
        final UserProfile(:level, :cheatSheetLimit) = profile.requireValue;
        return AsyncData(
          selectCheatSheetItems(
            value.sheet?.items ?? const [],
            above: level,
            limit: cheatSheetLimit,
            hidden: hidden,
          ),
        );
      }
      if (load case AsyncError(:final error, :final stackTrace)) {
        return AsyncError(error, stackTrace);
      }
      if (profile case AsyncError(:final error, :final stackTrace)) {
        return AsyncError(error, stackTrace);
      }
      return const AsyncLoading();
    }, name: 'cheatSheetItemsProvider');
