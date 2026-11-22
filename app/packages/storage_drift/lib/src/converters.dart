import 'dart:convert';

import 'package:core/domain_books.dart';
import 'package:core/domain_lookup.dart';
import 'package:drift/drift.dart';

/// Stores a [DateTime] as microseconds since the Unix epoch and reads it back
/// as UTC, so values survive a round trip without losing precision.
final class UtcDateTimeConverter extends TypeConverter<DateTime, int> {
  /// Creates the converter.
  const new();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMicrosecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.microsecondsSinceEpoch;
}

/// Stores a [Locator] as a JSON string.
final class LocatorConverter extends TypeConverter<Locator, String> {
  /// Creates the converter.
  const new();

  @override
  Locator fromSql(String fromDb) =>
      Locator.fromJson(jsonDecode(fromDb) as Map<String, Object?>);

  @override
  String toSql(Locator value) => jsonEncode(value.toJson());
}

/// Stores a [UserProfile] as a JSON string.
final class UserProfileConverter extends TypeConverter<UserProfile, String> {
  /// Creates the converter.
  const new();

  @override
  UserProfile fromSql(String fromDb) =>
      UserProfile.fromJson(jsonDecode(fromDb) as Map<String, Object?>);

  @override
  String toSql(UserProfile value) => jsonEncode(value.toJson());
}
