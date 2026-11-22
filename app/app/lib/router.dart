import 'package:features_history/features_history.dart';
import 'package:features_library/features_library.dart';
import 'package:features_settings/features_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/placeholder_screen.dart';

/// Route paths of the app.
abstract final class Routes {
  /// Library of books.
  static const library = '/library';

  /// Settings.
  static const settings = '/settings';

  /// History of lookups.
  static const history = '/history';

  /// Reader of a book: `/reader/<bookId>?locator=<json>`.
  static const reader = '/reader/:bookId';

  /// Cheat sheet before reading: `/cheatsheet/<bookId>`.
  static const cheatsheet = '/cheatsheet/:bookId';

  /// Location of the reader for [bookId], optionally at [locator].
  static String readerAt(String bookId, {String? locator}) => Uri(
    path: '/reader/$bookId',
    queryParameters: locator == null ? null : {'locator': locator},
  ).toString();

  /// Location of the cheat sheet for [bookId].
  static String cheatsheetFor(String bookId) => '/cheatsheet/$bookId';
}

/// Builds the app router, starting at [initialLocation].
GoRouter createRouter({String initialLocation = Routes.library}) {
  return GoRouter(
    initialLocation: initialLocation,
    // Navigation goes to the `GoRouter` logger (see logging.dart).
    debugLogDiagnostics: kDebugMode,
    routes: [
      GoRoute(path: '/', redirect: (_, _) => Routes.library),
      GoRoute(
        path: Routes.library,
        builder: (context, _) => LibraryScreen(
          onOpenBook: (id) => context.push(Routes.readerAt(id.value)),
        ),
      ),
      GoRoute(
        path: Routes.reader,
        builder: (_, state) => PlaceholderScreen(
          title: 'Reader',
          details: [
            'bookId: ${state.pathParameters['bookId']}',
            'locator: ${state.uri.queryParameters['locator'] ?? '-'}',
          ],
        ),
      ),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: Routes.history, builder: (_, _) => const HistoryScreen()),
      GoRoute(
        path: Routes.cheatsheet,
        builder: (_, state) => PlaceholderScreen(
          title: 'Cheat sheet',
          details: ['bookId: ${state.pathParameters['bookId']}'],
        ),
      ),
    ],
  );
}

/// The app router. Tests override it to start at another location.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final router = createRouter();
  ref.onDispose(router.dispose);
  return router;
});
