import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'router.dart';
import 'theme.dart';

/// Root widget: routing and light/dark theme following the system.
class MyReaderApp extends ConsumerWidget {
  /// Creates the root widget.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'My reader',
      theme: lightTheme(),
      darkTheme: darkTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
