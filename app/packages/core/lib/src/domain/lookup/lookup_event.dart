import 'package:meta/meta.dart';

import 'ids.dart';
import 'lookup_query.dart';
import 'lookup_result.dart';

/// Journal entry: one fact of a lookup. The source of truth for history.
@immutable
final class LookupEvent {
  /// Creates an event.
  const new({
    required this.id,
    required this.query,
    required this.result,
    required this.at,
  });

  /// Event id.
  final LookupEventId id;

  /// What was asked.
  final LookupQuery query;

  /// What was answered.
  final LookupResult result;

  /// When the lookup happened.
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is LookupEvent &&
      other.id == id &&
      other.query == query &&
      other.result == result &&
      other.at == at;

  @override
  int get hashCode => Object.hash(id, query, result, at);
}
