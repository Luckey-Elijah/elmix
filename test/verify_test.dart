import 'dart:io';

import 'package:test/test.dart';

void main() {
  final verifier = File('tool/verify.dart').absolute;

  group('workspace verification', () {
    late Directory fixture;

    setUp(() async {
      fixture = Directory.systemTemp.createTempSync('elmix-verify-');
      File('${fixture.path}/pubspec.yaml').writeAsStringSync('''
name: verification_fixture
environment:
  sdk: ^3.11.0
dev_dependencies:
  test: ^1.25.0
''');
      writeSource(
        fixture,
        'test/passing_test.dart',
        '''
import 'package:test/test.dart';

void main() {
  test('passes', () => expect(true, isTrue));
}
''',
      );
      final dependencies = await Process.run(
        Platform.resolvedExecutable,
        const <String>['pub', 'get'],
        workingDirectory: fixture.path,
      );
      if (dependencies.exitCode != 0) {
        throw StateError(dependencies.stderr.toString());
      }
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    test('passes a workspace without restrictive class modifiers', () async {
      writeSource(
        fixture,
        'packages/example/lib/example.dart',
        'class Example {}',
      );

      final result = await Process.run(
        Platform.resolvedExecutable,
        [verifier.path, '--root', fixture.path],
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('Workspace verification passed.'));
    });

    test(
      'fails when a package declares a restrictive class modifier',
      () async {
        writeSource(
          fixture,
          'packages/example/lib/example.dart',
          'sealed class Example {}',
        );

        final result = await Process.run(
          Platform.resolvedExecutable,
          [verifier.path, '--root', fixture.path],
        );

        expect(result.exitCode, 1);
        expect(result.stderr, contains('Restrictive Dart class modifiers'));
        expect(result.stderr, contains('sealed class'));
      },
    );

    test('fails when Dart analysis reports an error', () async {
      writeSource(
        fixture,
        'packages/example/lib/example.dart',
        'class Example {',
      );

      final result = await Process.run(
        Platform.resolvedExecutable,
        [verifier.path, '--root', fixture.path],
      );

      expect(result.exitCode, isNonZero);
      expect(result.stdout, contains('error'));
      expect(result.stdout, isNot(contains('Workspace verification passed.')));
    });

    test('fails when a workspace test fails', () async {
      writeSource(
        fixture,
        'test/failing_test.dart',
        '''
import 'package:test/test.dart';

void main() {
  test('intentional failure', () => fail('expected verification failure'));
}
''',
      );
      final result = await Process.run(
        Platform.resolvedExecutable,
        [verifier.path, '--root', fixture.path],
      );

      expect(result.exitCode, isNonZero);
      expect(result.stdout, isNot(contains('Workspace verification passed.')));
    });
  });
}

void writeSource(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
