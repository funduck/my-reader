import 'package:material_ui/material_ui.dart';

import 'bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    bootstrap(
      overrides: [...buildOverrides(), ...await buildDeviceOverrides()],
    ),
  );
}
