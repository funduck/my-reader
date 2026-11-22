import 'package:core/ports.dart';

/// An [IdGenerator] returning `<prefix>1`, `<prefix>2`, ... in order.
class SeqIdGenerator implements IdGenerator {
  /// Creates a generator; ids look like `id1` unless [prefix] is given.
  new({this.prefix = 'id'});

  /// Text put in front of the counter.
  final String prefix;

  int _next = 1;

  @override
  String newId() => '$prefix${_next++}';
}
