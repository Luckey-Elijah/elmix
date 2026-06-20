import 'dart:io';

import 'package:test/test.dart';

void main() {
  final checker = File('tool/check_core_v0_scope.dart').absolute;

  group('Core v0 scope check', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('elmix-core-v0-scope-');
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    test('accepts the Initial Module Set', () async {
      writeWorkspace(fixture, const [
        'elmix_engine',
        'elmix_sqlite',
        'elmix_server',
        'elmix_admin',
        'elmix_client',
        'elmix_cli',
      ]);

      final result = await Process.run(
        Platform.resolvedExecutable,
        [checker.path, '--root', fixture.path],
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('Core v0 workspace scope is valid.'));
    });

    test('rejects a future-only workspace package', () async {
      writeWorkspace(fixture, const [
        'elmix_engine',
        'elmix_sqlite',
        'elmix_server',
        'elmix_admin',
        'elmix_client',
        'elmix_cli',
        'elmix_files',
      ]);

      final result = await Process.run(
        Platform.resolvedExecutable,
        [checker.path, '--root', fixture.path],
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('elmix_files'));
      expect(result.stderr, contains('Initial Module Set'));
    });
  });
}

void writeWorkspace(Directory root, List<String> packages) {
  final lines = [
    'name: elmix',
    'workspace:',
    for (final package in packages) '  - packages/$package',
  ];
  File('${root.path}/pubspec.yaml').writeAsStringSync(lines.join('\n'));
}
