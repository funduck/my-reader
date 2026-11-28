import 'dart:async';

import 'package:core/domain_books.dart';
import 'package:features_cheatsheet/features_cheatsheet.dart';
import 'package:features_history/features_history.dart';
import 'package:features_library/features_library.dart';
import 'package:features_reader/features_reader.dart';
import 'package:features_settings/features_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lookup_sheet/lookup_sheet.dart';

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
          onOpenHistory: () => context.push(Routes.history),
          onOpenSettings: () => context.push(Routes.settings),
        ),
      ),
      GoRoute(
        path: Routes.reader,
        builder: (context, state) {
          final bookId = BookId(state.pathParameters['bookId']!);
          final param = state.uri.queryParameters['locator'];
          return ReaderScreen(
            key: ValueKey('${bookId.value}|$param'),
            bookId: bookId,
            locator: parseLocatorParam(param),
            onOpenHistory: () => context.push(Routes.history),
            onOpenSettings: () => context.push(Routes.settings),
            onOpenCheatSheet: (at) => context.push(
              Uri(
                path: Routes.cheatsheetFor(bookId.value),
                queryParameters: {'locator': encodeLocatorParam(at)},
              ).toString(),
            ),
          );
        },
      ),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: Routes.history,
        builder: (context, _) => HistoryScreen(
          onOpenLocation: (locator) => context.push(
            Routes.readerAt(
              locator.book.value,
              locator: encodeLocatorParam(locator),
            ),
          ),
        ),
      ),
      GoRoute(
        path: Routes.cheatsheet,
        builder: (context, state) {
          final bookId = BookId(state.pathParameters['bookId']!);
          final param = state.uri.queryParameters['locator'];
          return CheatSheetScreen(
            key: ValueKey('${bookId.value}|$param'),
            bookId: bookId,
            from: parseLocatorParam(param),
            onWordTap: (sheetContext, query) => unawaited(
              showLookupSheet(
                sheetContext,
                query,
                onOpenSettings: () => context.push(Routes.settings),
              ),
            ),
            onRead: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(Routes.readerAt(bookId.value));
              }
            },
          );
        },
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
