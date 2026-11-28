import 'dart:async';

import 'package:core/domain_books.dart' show BookId;
import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import 'router.dart';

final Logger _log = Logger('LastScreen');

/// The last screen that [location] (a path of the router) stands for.
///
/// Reader and cheat sheet give their book. The library gives `null`, which
/// clears the record. History, settings and anything else are not `defined`:
/// they leave the record as it is, so a restart from there opens the book
/// the user came from.
({bool defined, LastScreen? screen}) lastScreenOf(String location) {
  final segments = Uri.parse(location).pathSegments;
  if (segments.isEmpty || segments.first == 'library') {
    return (defined: true, screen: null);
  }
  if (segments.length == 2 && segments[1].isNotEmpty) {
    final kind = switch (segments.first) {
      'reader' => LastScreenKind.reader,
      'cheatsheet' => LastScreenKind.cheatsheet,
      _ => null,
    };
    if (kind != null) {
      return (
        defined: true,
        screen: LastScreen(kind: kind, book: BookId(segments[1])),
      );
    }
  }
  return (defined: false, screen: null);
}

/// Path of the screen to open for [screen].
String locationOf(LastScreen screen) => switch (screen.kind) {
  LastScreenKind.reader => Routes.readerAt(screen.book.value),
  LastScreenKind.cheatsheet => Routes.cheatsheetFor(screen.book.value),
};

/// Keeps `UserProfile.lastScreen` equal to the reader or cheat sheet the
/// router shows, through `ProfileRepository.update`.
final class LastScreenTracker {
  /// Starts to follow the router. `stored` is the record now in the profile.
  new(this._router, this._profiles, {required this._stored}) {
    _router.routerDelegate.addListener(_onChange);
    _onChange();
  }

  final GoRouter _router;
  final ProfileRepository _profiles;
  LastScreen? _stored;
  bool _disposed = false;

  void _onChange() {
    final configuration = _router.routerDelegate.currentConfiguration;
    if (configuration.isEmpty) return;
    final target = lastScreenOf(configuration.last.matchedLocation);
    if (!target.defined) return;
    final screen = target.screen;
    if (screen == _stored) return;
    _stored = screen;
    unawaited(_write(screen));
  }

  Future<void> _write(LastScreen? screen) async {
    try {
      await _profiles.update((p) => p.copyWith(lastScreen: () => screen));
    } on Object catch (e, s) {
      _log.warning('Cannot save the last screen', e, s);
    }
  }

  /// Stops following the router.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _router.routerDelegate.removeListener(_onChange);
  }
}

/// How long launch waits for the router before it gives up restoring.
const Duration _routerTimeout = Duration(seconds: 5);

/// Completes once [done] is true; [done] is checked on every change of the
/// router. Throws `TimeoutException` after [_routerTimeout].
Future<void> _waitFor(GoRouter router, bool Function() done) {
  if (done()) return Future<void>.value();
  final completer = Completer<void>();
  void check() {
    if (done() && !completer.isCompleted) completer.complete();
  }

  router.routerDelegate.addListener(check);
  return completer.future
      .timeout(_routerTimeout)
      .whenComplete(() => router.routerDelegate.removeListener(check));
}

/// Launch: opens the stored reader or cheat sheet over the library, then
/// starts to track the screens. `MyReaderApp` hides the router until it is
/// done.
///
/// A record whose book is not in the library is erased and the app stays on
/// the library. A profile or book store that cannot be read also leaves the
/// library (and nothing is tracked).
final FutureProvider<void> launchProvider = FutureProvider<void>((ref) async {
  final router = ref.read(routerProvider);
  final ProfileRepository profiles;
  LastScreen? stored;
  try {
    profiles = ref.read(profileRepositoryProvider);
    stored = (await profiles.get()).lastScreen;
    if (stored != null) {
      final book = await ref.read(bookRepositoryProvider).get(stored.book);
      if (book == null) {
        _log.info('The book ${stored.book.value} is gone, opening the library');
        await profiles.update((p) => p.copyWith(lastScreen: () => null));
        stored = null;
      }
    }
  } on Object catch (e, s) {
    _log.warning('Cannot read the last screen', e, s);
    return;
  }
  if (stored != null) {
    try {
      await _restore(router, stored);
    } on Object catch (e, s) {
      _log.warning('Cannot restore $stored', e, s);
    }
  }
  final tracker = LastScreenTracker(router, profiles, stored: stored);
  ref.onDispose(tracker.dispose);
});

/// Pushes [screen] over the library once the router has shown the library:
/// a push before that has nothing under it.
Future<void> _restore(GoRouter router, LastScreen screen) async {
  _log.info('Restoring $screen');
  await _waitFor(
    router,
    () => router.routerDelegate.currentConfiguration.isNotEmpty,
  );
  unawaited(
    router.push<void>(
      locationOf(screen),
      extra: screen.kind == LastScreenKind.cheatsheet
          ? restoredCheatSheet
          : null,
    ),
  );
  await _waitFor(
    router,
    () =>
        lastScreenOf(
          router.routerDelegate.currentConfiguration.last.matchedLocation,
        ).screen ==
        screen,
  );
}
