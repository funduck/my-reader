// Latency of WiktionaryLookupProvider on a full en-en pack.
//
// Usage (from app/packages/lookup_wiktionary):
//   dart run benchmark/lookup_benchmark.dart /path/to/en-en-<version>.sqlite
//
// Picks 100 random keys (fixed seed), looks each up on a warm provider and
// prints p50/p95/max in milliseconds. The pack is only read, never copied.
import 'dart:io';
import 'dart:math';

import 'package:core/domain_lookup.dart';
import 'package:core/ports.dart';
import 'package:lookup_wiktionary/lookup_wiktionary.dart';
import 'package:sqlite3/sqlite3.dart';

class _FixedPathStore implements PackStore {
  const new(this.path);

  final String path;

  @override
  Future<String?> pathOf(String id) async => path;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run benchmark/lookup_benchmark.dart <pack>');
    exit(64);
  }
  final path = args.single;
  final random = Random(44);

  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  final maxId = db.select('SELECT max(id) AS m FROM entries').first['m'] as int;
  final keys = <String>{};
  while (keys.length < 100) {
    final rows = db.select('SELECT key FROM entries WHERE id >= ? LIMIT 1', [
      random.nextInt(maxId) + 1,
    ]);
    if (rows.isNotEmpty) keys.add(rows.first['key'] as String);
  }
  db.close();

  final provider = WiktionaryLookupProvider(packStore: _FixedPathStore(path));
  const mode = LookupMode.enEn;

  final openWatch = Stopwatch()..start();
  await provider.lookup(const LookupQuery(text: 'go', mode: mode));
  openWatch.stop();

  final micros = <int>[];
  for (final key in keys) {
    final watch = Stopwatch()..start();
    try {
      await provider.lookup(LookupQuery(text: key, mode: mode));
    } on LookupFailure {
      // Still counts: a miss costs a query too.
    }
    watch.stop();
    micros.add(watch.elapsedMicroseconds);
  }
  provider.close();

  micros.sort();
  double ms(int index) => micros[index] / 1000;
  stdout
    ..writeln('pack: $path')
    ..writeln('first lookup incl. open: ${openWatch.elapsedMilliseconds} ms')
    ..writeln('words: ${micros.length}')
    ..writeln('p50: ${ms(micros.length ~/ 2).toStringAsFixed(2)} ms')
    ..writeln(
      'p95: ${ms((micros.length * 95 / 100).ceil() - 1).toStringAsFixed(2)} ms',
    )
    ..writeln('max: ${ms(micros.length - 1).toStringAsFixed(2)} ms');
}
