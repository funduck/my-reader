import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'bootstrap.dart';
import 'logging.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  setUpLogging(
    file: File(
      '${support.path}${Platform.pathSeparator}logs'
      '${Platform.pathSeparator}app.log',
    ),
  );
  runApp(
    bootstrap(
      overrides: [...buildOverrides(), ...await buildDeviceOverrides()],
    ),
  );
}
