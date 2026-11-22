import 'dart:convert';

import 'package:core/domain_books.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('LocatorParam');

/// Parses the `locator` query parameter of the reader route (JSON of
/// [Locator.toJson]). Returns null for a missing or malformed value, so the
/// reader falls back to the saved position.
Locator? parseLocatorParam(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    final json = jsonDecode(value);
    if (json is! Map<String, Object?>) return null;
    return Locator.fromJson(json);
  } on Object catch (e, s) {
    _log.warning('Bad locator parameter', e, s);
    return null;
  }
}

/// The value for the `locator` query parameter that [parseLocatorParam]
/// reads back.
String encodeLocatorParam(Locator locator) => jsonEncode(locator.toJson());
