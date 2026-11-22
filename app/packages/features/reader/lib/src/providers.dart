import 'package:core/application.dart';
import 'package:core/domain_books.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The use case that opens a book and finds its saved position.
final Provider<OpenBook> openBookProvider = Provider<OpenBook>(
  (ref) => OpenBook(
    adapters: ref.watch(bookFormatsProvider),
    books: ref.watch(bookRepositoryProvider),
    progress: ref.watch(progressRepositoryProvider),
  ),
  name: 'openBookProvider',
);

/// The use case that saves the reading position.
final Provider<SaveProgress> saveProgressProvider = Provider<SaveProgress>(
  (ref) => SaveProgress(
    progress: ref.watch(progressRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
  name: 'saveProgressProvider',
);

/// Shows the lookup of a word or phrase the user picked in the text.
///
/// [text] is the tapped word or the selection, [at] where it starts in the
/// book and [sentence] the sentence around it (context for the history).
/// Completes when the lookup UI is closed.
typedef LookupPresenter = Future<void> Function(
  BuildContext context, {
  required String text,
  required Locator at,
  required String sentence,
});

/// How the reader shows a lookup.
///
/// A feature must not import another feature, so `app` overrides this with a
/// function that opens `showLookupSheet`. Throws `PortNotWiredError` until
/// then.
final Provider<LookupPresenter> lookupPresenterProvider =
    Provider<LookupPresenter>(
      (ref) => throw PortNotWiredError('lookupPresenterProvider'),
      name: 'lookupPresenterProvider',
    );
