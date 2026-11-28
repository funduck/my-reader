/// Riverpod providers of core ports and the label and toggle widgets shared
/// by features and the app.
///
/// Every provider here throws until `app/lib/bootstrap.dart` overrides it with
/// a concrete implementation (`ProviderScope(overrides: [...])`). Features
/// read ports only through these providers and never import `app`.
library;

export 'src/dictionary_library.dart';
export 'src/font_loading.dart';
export 'src/info_label.dart';
export 'src/level_badge.dart';
export 'src/port_providers.dart';
export 'src/scenario_providers.dart';
export 'src/toggle_button.dart';
