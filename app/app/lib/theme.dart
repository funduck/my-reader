import 'package:material_ui/material_ui.dart';

const _seed = Color(0xFF3F5F8F);

/// Light theme of the app.
ThemeData lightTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _seed),
  useMaterial3: true,
);

/// Dark theme of the app.
ThemeData darkTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
);
