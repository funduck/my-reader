import 'package:material_ui/material_ui.dart';

import 'demo/demo_app.dart';
import 'logging.dart';

/// Demo app: the real screens over in-memory demo data (T-109).
///
/// `flutter run -d macos -t lib/main_demo.dart` shows the list of scenarios;
/// `--dart-define=SCENARIO=<id>` opens one right away (ids are in
/// `demo/scenarios.dart`). Logs go to the console only.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setUpLogging();
  const scenario = String.fromEnvironment('SCENARIO');
  runApp(DemoApp(initial: scenario.isEmpty ? null : scenario));
}
