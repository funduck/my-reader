import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';

import 'app.dart';

/// Overrides of the port providers: the only place where concrete
/// implementations are chosen (docs/Architecture-app.md, section 8).
///
/// Ports that have no implementation yet are not overridden, so reading them
/// throws `PortNotWiredError`. Other tasks add their lines here.
List<Override> buildOverrides() => [
  clockProvider.overrideWithValue(const SystemClock()),
  idGeneratorProvider.overrideWithValue(CounterIdGenerator()),
];

/// Builds the root widget with all providers wired.
Widget bootstrap({List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? buildOverrides(),
    child: const MyReaderApp(),
  );
}

/// [Clock] backed by the system time.
class SystemClock implements Clock {
  /// Creates the clock.
  const new();

  @override
  DateTime now() => DateTime.now();
}

/// [IdGenerator] that combines the start time with a counter.
///
/// Placeholder until a real generator (uuid) is chosen.
class CounterIdGenerator implements IdGenerator {
  /// Creates the generator.
  new() : _prefix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  final String _prefix;
  int _next = 0;

  @override
  String newId() => '$_prefix-${(_next++).toRadixString(36)}';
}
