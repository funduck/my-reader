// Checks the dependency rules of the app/ workspace from pubspec.yaml files.
//
// Rules (docs/Architecture-app.md, section 1):
//   core      -> only Dart SDK and pure utilities (no Flutter, SQLite, HTTP)
//   adapters  -> core only (dev: core_testing)
//   features  -> core, reader_api and features_common, never adapters or
//                other features (dev: core_testing)
//   features_common (packages/features/common) -> core and reader_api
//   app/app   -> everything, the only place that wires concrete adapters
//
// The kind of a package comes from its directory, see [kindOfPath].
// Run: dart run tool/check_imports.dart  (from app/)
import 'dart:io';

import 'package:yaml/yaml.dart';

/// What role a workspace package plays in the architecture.
enum PackageKind {
  /// The application itself, the composition root.
  app('app'),

  /// Pure Dart domain model, ports and use cases.
  core('core'),

  /// Fakes and contract tests for adapters.
  testing('core_testing'),

  /// Reader engine contract.
  api('reader_api'),

  /// Reader engine implementation (`reader_*`).
  renderer('renderer'),

  /// Any other package under `packages/`: formats, lookup, storage, text...
  adapter('adapter'),

  /// Shared providers of ports for features: `packages/features/common`.
  featuresCommon('features_common'),

  /// A UI feature under `packages/features/`.
  feature('feature');

  new(this.label);

  /// Name used in messages.
  final String label;
}

/// A rule violation with a human readable message.
class Violation {
  /// Creates a violation of [message] found in [packageDir].
  const new(this.packageDir, this.message);

  /// Package directory (or file) relative to the workspace root.
  final String packageDir;

  /// What is wrong and how to fix it.
  final String message;

  @override
  String toString() => '$packageDir: $message';
}

/// Packages that must never be reachable from `core`, besides anything that
/// depends on the Flutter SDK.
const _forbiddenInCore = {
  'drift',
  'drift_dev',
  'sqlite3',
  'sqlite3_flutter_libs',
  'http',
  'dio',
  'riverpod',
  'go_router',
  'path_provider',
  'shared_preferences',
};

final _forbiddenImport = RegExp(
  r'''^\s*(?:import|export|part)\s+['"](?:dart:(?:ui|html|js|js_interop|js_util)|package:flutter(?:_\w+)?/)''',
  multiLine: true,
);

/// Derives the kind of the package at [relPath] (posix, relative to the
/// workspace root), or null if the layout is not recognised.
PackageKind? kindOfPath(String relPath) {
  final parts = relPath.split('/');
  if (relPath == 'app') return PackageKind.app;
  if (parts.length < 2 || parts.first != 'packages') return null;
  if (parts.length == 3 && parts[1] == 'features') {
    return parts[2] == 'common'
        ? PackageKind.featuresCommon
        : PackageKind.feature;
  }
  if (parts.length != 2) return null;
  final name = parts[1];
  if (name == 'core') return PackageKind.core;
  if (name == 'core_testing') return PackageKind.testing;
  if (name == 'reader_api') return PackageKind.api;
  if (name.startsWith('reader_')) return PackageKind.renderer;
  return PackageKind.adapter;
}

/// Kinds a package of [kind] may depend on in `dependencies`.
Set<PackageKind> _allowedInternal(PackageKind kind) => switch (kind) {
  PackageKind.app => PackageKind.values.toSet(),
  PackageKind.core => {},
  PackageKind.testing => {PackageKind.core},
  PackageKind.api => {PackageKind.core},
  PackageKind.renderer => {PackageKind.core, PackageKind.api},
  PackageKind.adapter => {PackageKind.core},
  PackageKind.featuresCommon => {PackageKind.core, PackageKind.api},
  PackageKind.feature => {
    PackageKind.core,
    PackageKind.api,
    PackageKind.featuresCommon,
  },
};

class _Package {
  new(this.dir, this.name, this.kind, this.pubspec);

  final String dir;
  final String name;
  final PackageKind kind;
  final YamlMap pubspec;

  Map<String, Object?> section(String key) {
    final value = pubspec[key];
    if (value is! YamlMap) return const {};
    return {for (final e in value.entries) e.key as String: e.value};
  }
}

bool _isFlutterSdk(Object? spec) => spec is YamlMap && spec['sdk'] == 'flutter';

/// Checks every package of the workspace at [root] (the directory with the
/// root `pubspec.yaml`) and returns all violations found.
List<Violation> checkImports(Directory root) {
  final violations = <Violation>[];
  final rootPubspec = loadYaml(
    File('${root.path}/pubspec.yaml').readAsStringSync(),
  );
  final members = rootPubspec is YamlMap ? rootPubspec['workspace'] : null;
  if (members is! YamlList) {
    return [
      const Violation('.', 'pubspec.yaml has no `workspace:` list of packages'),
    ];
  }

  final packages = <_Package>[];
  for (final member in members) {
    final dir = (member as String).replaceAll(r'\', '/');
    final kind = kindOfPath(dir);
    if (kind == null) {
      violations.add(
        Violation(
          dir,
          'cannot tell what kind of package this is. Allowed locations: '
          'app, packages/core, packages/core_testing, packages/reader_api, '
          'packages/reader_*, packages/features/<name>, packages/<adapter>',
        ),
      );
      continue;
    }
    final yaml = loadYaml(
      File('${root.path}/$dir/pubspec.yaml').readAsStringSync(),
    );
    packages.add(
      _Package(dir, (yaml as YamlMap)['name'] as String, kind, yaml),
    );
  }

  final byName = {for (final p in packages) p.name: p};
  for (final p in packages) {
    _checkPackage(p, byName, violations);
  }
  for (final p in packages.where((p) => p.kind == PackageKind.core)) {
    _checkCoreSources(root, p, violations);
  }
  return violations;
}

void _checkPackage(
  _Package p,
  Map<String, _Package> byName,
  List<Violation> out,
) {
  final label = p.kind.label;
  final allowed = _allowedInternal(p.kind);
  for (final section in ['dependencies', 'dev_dependencies']) {
    final isDev = section == 'dev_dependencies';
    for (final MapEntry(key: dep, value: spec) in p.section(section).entries) {
      final target = byName[dep];
      if (target != null) {
        final isFakes = target.kind == PackageKind.testing;
        if (isFakes &&
            !isDev &&
            p.kind != PackageKind.app &&
            p.kind != PackageKind.testing) {
          out.add(
            Violation(
              p.dir,
              '$label package `${p.name}` has core_testing in '
              '`dependencies`; fakes belong in `dev_dependencies`.',
            ),
          );
        } else if (!allowed.contains(target.kind) &&
            !(isDev && isFakes && p.kind != PackageKind.core)) {
          final allowedText = allowed.isEmpty
              ? 'nothing from this workspace'
              : allowed.map((k) => k.label).join(', ');
          out.add(
            Violation(
              p.dir,
              '$label package `${p.name}` depends on `$dep` '
              '(${target.kind.label}) in `$section`. A $label may depend '
              'only on: $allowedText. Only app/app wires concrete adapters '
              '(docs/Architecture-app.md, section 1).',
            ),
          );
        }
        continue;
      }
      if (p.kind == PackageKind.core &&
          (_isFlutterSdk(spec) ||
              dep.startsWith('flutter') ||
              _forbiddenInCore.contains(dep))) {
        out.add(
          Violation(
            p.dir,
            'core depends on `$dep` in `$section`. core must be pure Dart: '
            'no Flutter, SQLite or HTTP (docs/Architecture-app.md, '
            'section 1, rule 1). Move the code to an adapter.',
          ),
        );
      }
    }
  }
  if (p.kind != PackageKind.app) {
    for (final dep in p.section('dependency_overrides').keys) {
      out.add(
        Violation(
          p.dir,
          '$label package `${p.name}` has `dependency_overrides` for `$dep`; '
          'overrides can hide a forbidden dependency.',
        ),
      );
    }
  }
}

void _checkCoreSources(Directory root, _Package p, List<Violation> out) {
  for (final sub in ['lib', 'test']) {
    final dir = Directory('${root.path}/${p.dir}/$sub');
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final match = _forbiddenImport.firstMatch(file.readAsStringSync());
      if (match != null) {
        final rel = file.path.substring(root.path.length + 1);
        out.add(
          Violation(
            rel,
            'core imports Flutter or a web/UI library: '
            '`${match.group(0)!.trim()}`. core must be pure Dart.',
          ),
        );
      }
    }
  }
}

/// Entry point: checks the workspace in the current directory.
void main() {
  final violations = checkImports(Directory.current);
  if (violations.isEmpty) {
    stdout.writeln('check_imports: OK');
    return;
  }
  stderr.writeln('check_imports: ${violations.length} violation(s)');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  exit(1);
}
