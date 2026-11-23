import 'package:meta/meta.dart';

import '../../../domain_books.dart';
import 'ids.dart';

/// One translated selection of several words (a phrase), kept apart from the
/// words and terms of the history.
///
/// The text is stored as selected ("gave up", "giving it up"): variants of one
/// construction are not merged here, every entry has its own stable [id].
@immutable
final class PhraseLookup {
  /// Creates an entry. [at] should be in UTC.
  const new({
    required this.id,
    required this.text,
    required this.translation,
    required this.provider,
    required this.at,
    required this.locator,
    this.sentence,
  });

  /// Restores an entry from [toJson] output.
  factory fromJson(Map<String, Object?> json) => PhraseLookup(
    id: PhraseLookupId(json['id']! as String),
    text: json['text']! as String,
    translation: json['translation']! as String,
    provider: ProviderId(json['provider']! as String),
    at: DateTime.fromMicrosecondsSinceEpoch(json['at']! as int, isUtc: true),
    locator: Locator.fromJson(json['locator']! as Map<String, Object?>),
    sentence: json['sentence'] as String?,
  );

  /// Stable id of the entry.
  final PhraseLookupId id;

  /// The phrase as selected by the user.
  final String text;

  /// Translation of [text].
  final String translation;

  /// Provider that gave the [translation].
  final ProviderId provider;

  /// When the phrase was translated.
  final DateTime at;

  /// Place of the selection in the book.
  final Locator locator;

  /// Sentence around the selection, if known.
  final String? sentence;

  /// Serializes the entry; [at] is microseconds since the epoch (UTC).
  Map<String, Object?> toJson() => {
    'id': id.value,
    'text': text,
    'translation': translation,
    'provider': provider.value,
    'at': at.microsecondsSinceEpoch,
    'locator': locator.toJson(),
    if (sentence != null) 'sentence': sentence,
  };

  @override
  bool operator ==(Object other) =>
      other is PhraseLookup &&
      other.id == id &&
      other.text == text &&
      other.translation == translation &&
      other.provider == provider &&
      other.at == at &&
      other.locator == locator &&
      other.sentence == sentence;

  @override
  int get hashCode =>
      Object.hash(id, text, translation, provider, at, locator, sentence);

  @override
  String toString() => 'PhraseLookup($id, $text)';
}
