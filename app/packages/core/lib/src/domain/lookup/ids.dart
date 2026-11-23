/// Identifiers used by the lookup domain.
library;

import 'package:meta/meta.dart';

/// Identifier of a lookup provider, e.g. `llm.openai` or
/// `stardict.freedict-eng-rus`.
@immutable
final class ProviderId {
  /// Creates an id from its string [value].
  const new(this.value);

  /// Raw id string.
  final String value;

  @override
  bool operator ==(Object other) => other is ProviderId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ProviderId($value)';
}

/// Identifier of a term aggregate.
@immutable
final class TermId {
  /// Creates an id from its string [value].
  const new(this.value);

  /// Raw id string.
  final String value;

  @override
  bool operator ==(Object other) => other is TermId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TermId($value)';
}

/// Identifier of a journal entry (`LookupEvent`).
@immutable
final class LookupEventId {
  /// Creates an id from its string [value].
  const new(this.value);

  /// Raw id string.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is LookupEventId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'LookupEventId($value)';
}

/// Identifier of a phrase journal entry (`PhraseLookup`).
@immutable
final class PhraseLookupId {
  /// Creates an id from its string [value].
  const new(this.value);

  /// Raw id string.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is PhraseLookupId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PhraseLookupId($value)';
}
