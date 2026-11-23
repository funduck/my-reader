/// Riverpod providers of core ports, shared by features and the app.
///
/// Every provider here throws until `app/lib/bootstrap.dart` overrides it with
/// a concrete implementation (`ProviderScope(overrides: [...])`). Features
/// read ports only through these providers and never import `app`.
library;

export 'src/dictionary_library.dart';
export 'src/font_loading.dart';
export 'src/port_providers.dart';
