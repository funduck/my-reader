/// Lookup bottom sheet: opens at once with a skeleton, then shows the word,
/// IPA, parts of speech, senses with examples and the provider name.
///
/// Other features call `showLookupSheet`. The app wires only the port
/// providers of `features_common`.
library;

export 'src/lookup_providers.dart';
export 'src/lookup_sheet.dart';
export 'src/simple_html.dart' show SimpleHtml, looksLikeHtml, parseSimpleHtml;
