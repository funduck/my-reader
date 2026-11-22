final RegExp _spaces = RegExp(r'\s+');
final RegExp _apostrophes = RegExp('[’‘ʼ′]');

/// Normalizes [text] into a pack key.
///
/// Same rules as `normalize_key` in `service/build/schema.py`: typographic
/// apostrophes become `'`, lower case, whitespace runs collapse to one space,
/// edges are trimmed. Hyphens and other punctuation stay.
String normalizeKey(String text) => text
    .replaceAll(_apostrophes, "'")
    .toLowerCase()
    .replaceAll(_spaces, ' ')
    .trim();
