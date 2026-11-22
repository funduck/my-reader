import 'package:core/ports.dart';
import 'package:features_common/features_common.dart';
import 'package:features_library/features_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:format_epub/format_epub.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:storage_drift/storage_drift.dart';

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

/// Overrides that need the device: the drift database file and the directory
/// of imported books, both in the application support directory, plus the
/// repositories and format adapters on top of them.
///
/// Call once before `runApp` and pass `[...buildOverrides(), ...these]`.
Future<List<Override>> buildDeviceOverrides() async {
  final support = await getApplicationSupportDirectory();
  await support.create(recursive: true);
  final database = openDatabase('${support.path}/my_reader.sqlite');
  return [
    bookRepositoryProvider.overrideWithValue(database.bookRepository),
    progressRepositoryProvider.overrideWithValue(database.progressRepository),
    profileRepositoryProvider.overrideWithValue(database.profileRepository),
    bookFormatsProvider.overrideWithValue(const [EpubFormatAdapter()]),
    booksDirectoryProvider.overrideWithValue('${support.path}/books'),
  ];
}

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
