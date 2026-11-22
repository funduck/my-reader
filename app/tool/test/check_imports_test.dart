import 'dart:io';

import 'package:test/test.dart';

import '../check_imports.dart';

/// Builds a throwaway workspace: [packages] maps a directory to the body of
/// its pubspec (below `name` and `resolution`).
Directory _workspace(Map<String, String> packages) {
  final root = Directory.systemTemp.createTempSync('check_imports_');
  addTearDown(() => root.deleteSync(recursive: true));
  final members = packages.keys.map((d) => '  - $d').join('\n');
  File('${root.path}/pubspec.yaml')
      .writeAsStringSync('name: ws\nworkspace:\n$members\n');
  packages.forEach((dir, body) {
    Directory('${root.path}/$dir').createSync(recursive: true);
    final name = dir.split('/').last;
    File('${root.path}/$dir/pubspec.yaml')
        .writeAsStringSync('name: $name\nresolution: workspace\n$body\n');
  });
  return root;
}

const _flutter = 'dependencies:\n  flutter:\n    sdk: flutter';

void main() {
  test('a valid layout passes', () {
    final root = _workspace({
      'app':
          'dependencies:\n  core: any\n  reader_api: any\n'
          '  storage_drift: any\n  library: any\n  flutter:\n'
          '    sdk: flutter',
      'packages/core': 'dev_dependencies:\n  test: any',
      'packages/core_testing': 'dependencies:\n  core: any',
      'packages/reader_api':
          'dependencies:\n  core: any\n  flutter:\n    sdk: flutter',
      'packages/reader_simple':
          'dependencies:\n  core: any\n  reader_api: any\n  flutter:\n'
          '    sdk: flutter',
      'packages/storage_drift':
          'dependencies:\n  core: any\n  drift: any\n'
          'dev_dependencies:\n  core_testing: any',
      'packages/features/library':
          'dependencies:\n  core: any\n  reader_api: any\n  flutter:\n'
          '    sdk: flutter\ndev_dependencies:\n  core_testing: any',
    });
    expect(checkImports(root), isEmpty);
  });

  group('core', () {
    test('depending on flutter fails with a clear message', () {
      final root = _workspace({'packages/core': _flutter});
      final v = checkImports(root);
      expect(v, hasLength(1));
      expect(v.single.packageDir, 'packages/core');
      expect(v.single.message, contains('core depends on `flutter`'));
      expect(v.single.message, contains('pure Dart'));
    });

    test('flutter_test in dev_dependencies fails', () {
      final root = _workspace({
        'packages/core': 'dev_dependencies:\n  flutter_test:\n    sdk: flutter',
      });
      expect(checkImports(root).single.message, contains('flutter_test'));
    });

    test('sqlite and http fail, pure utilities pass', () {
      final root = _workspace({
        'packages/core':
            'dependencies:\n  sqlite3: any\n  http: any\n'
            '  meta: any\n  collection: any',
      });
      final v = checkImports(root);
      expect(v, hasLength(2));
      expect(v.map((e) => e.message).join(), isNot(contains('`meta`')));
    });

    test('depending on another workspace package fails', () {
      final root = _workspace({
        'packages/core': 'dependencies:\n  reader_api: any',
        'packages/reader_api': 'dependencies:\n  core: any',
      });
      expect(
        checkImports(root).single.message,
        contains('nothing from this workspace'),
      );
    });

    test('core_testing in dev_dependencies of core fails', () {
      final root = _workspace({
        'packages/core': 'dev_dependencies:\n  core_testing: any',
        'packages/core_testing': 'dependencies:\n  core: any',
      });
      expect(checkImports(root), hasLength(1));
    });

    test('importing flutter in source fails', () {
      final root = _workspace({'packages/core': ''});
      Directory('${root.path}/packages/core/lib').createSync(recursive: true);
      File('${root.path}/packages/core/lib/a.dart')
          .writeAsStringSync("import 'package:flutter/widgets.dart';\n");
      final v = checkImports(root);
      expect(v.single.packageDir, 'packages/core/lib/a.dart');
    });
  });

  group('adapters and features', () {
    test('adapter depending on another adapter fails', () {
      final root = _workspace({
        'packages/core': '',
        'packages/format_epub':
            'dependencies:\n  core: any\n  storage_drift: any',
        'packages/storage_drift': 'dependencies:\n  core: any',
      });
      final v = checkImports(root);
      expect(v.single.packageDir, 'packages/format_epub');
      expect(v.single.message, contains('`storage_drift`'));
    });

    test('adapter depending on reader_api fails', () {
      final root = _workspace({
        'packages/core': '',
        'packages/reader_api': 'dependencies:\n  core: any',
        'packages/lookup_x': 'dependencies:\n  reader_api: any',
      });
      expect(checkImports(root).single.packageDir, 'packages/lookup_x');
    });

    test('feature depending on an adapter fails', () {
      final root = _workspace({
        'packages/core': '',
        'packages/storage_drift': 'dependencies:\n  core: any',
        'packages/features/history':
            'dependencies:\n  core: any\n  storage_drift: any',
      });
      final v = checkImports(root);
      expect(v.single.packageDir, 'packages/features/history');
      expect(
        v.single.message,
        contains('only on: core, reader_api, features_common'),
      );
    });

    test('feature depending on a renderer or another feature fails', () {
      final root = _workspace({
        'packages/core': '',
        'packages/reader_simple': 'dependencies:\n  core: any',
        'packages/features/a': 'dependencies:\n  reader_simple: any',
        'packages/features/b': 'dependencies:\n  a: any',
      });
      expect(checkImports(root), hasLength(2));
    });

    test('feature may depend on features_common, not the reverse', () {
      final root = _workspace({
        'packages/core': '',
        'packages/features/common': 'dependencies:\n  core: any',
        'packages/features/lookup_sheet':
            'dependencies:\n  core: any\n  common: any',
      });
      expect(checkImports(root), isEmpty);

      final bad = _workspace({
        'packages/core': '',
        'packages/features/common': 'dependencies:\n  lookup_sheet: any',
        'packages/features/lookup_sheet': 'dependencies:\n  core: any',
      });
      expect(checkImports(bad).single.packageDir, 'packages/features/common');
    });

    test('core_testing in dependencies fails', () {
      final root = _workspace({
        'packages/core': '',
        'packages/core_testing': 'dependencies:\n  core: any',
        'packages/storage_drift':
            'dependencies:\n  core: any\n  core_testing: any',
      });
      expect(checkImports(root).single.message, contains('dev_dependencies'));
    });

    test('dependency_overrides outside app fails', () {
      final root = _workspace({
        'packages/core': '',
        'packages/storage_drift': 'dependency_overrides:\n  core: any',
      });
      expect(checkImports(root).single.message, contains('overrides'));
    });
  });

  group('script', () {
    final script = File('tool/check_imports.dart').absolute.path;

    test('exits 1 with the message when core depends on flutter', () {
      final root = _workspace({'packages/core': _flutter});
      final r = Process.runSync(Platform.resolvedExecutable, [
        'run',
        script,
      ], workingDirectory: root.path);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('core depends on `flutter`'));
    });

    test('exits 0 on a clean workspace', () {
      final root = _workspace({'packages/core': ''});
      final r = Process.runSync(Platform.resolvedExecutable, [
        'run',
        script,
      ], workingDirectory: root.path);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('OK'));
    });
  });

  group('layout', () {
    test('unknown directory fails', () {
      final root = _workspace({'misc/thing': ''});
      expect(checkImports(root).single.message, contains('cannot tell'));
    });

    test('kindOfPath', () {
      expect(kindOfPath('app'), PackageKind.app);
      expect(kindOfPath('packages/core'), PackageKind.core);
      expect(kindOfPath('packages/core_testing'), PackageKind.testing);
      expect(kindOfPath('packages/reader_api'), PackageKind.api);
      expect(kindOfPath('packages/reader_simple'), PackageKind.renderer);
      expect(kindOfPath('packages/features/library'), PackageKind.feature);
      expect(
        kindOfPath('packages/features/common'),
        PackageKind.featuresCommon,
      );
      expect(kindOfPath('packages/text_en'), PackageKind.adapter);
    });
  });
}
