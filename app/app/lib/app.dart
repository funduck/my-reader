import 'package:core/domain_lookup.dart' show DisplayMode;
import 'package:features_settings/features_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'last_screen.dart';
import 'router.dart';
import 'theme.dart';

/// Root widget: routing and the light/dark theme of the reading mode
/// (the system theme until the profile is read).
class MyReaderApp extends ConsumerWidget {
  /// Creates the root widget.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      profileProvider.select((p) => p.value?.display.mode),
    );
    return MaterialApp.router(
      title: 'My reader',
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: switch (mode) {
        DisplayMode.day => ThemeMode.light,
        DisplayMode.night => ThemeMode.dark,
        null => ThemeMode.system,
      },
      routerConfig: ref.watch(routerProvider),
      // The library below is hidden while launch opens the last screen over
      // it (B-030), so a restored book does not flash the library first.
      builder: (context, child) => Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.expand,
        children: [
          ?child,
          if (ref.watch(launchProvider).isLoading)
            ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
        ],
      ),
    );
  }
}
