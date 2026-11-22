import 'package:core/application.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
