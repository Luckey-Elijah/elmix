import 'dart:io';

import 'package:test/test.dart';

void main() {
  final checker = File('tool/check_restrictive_class_modifiers.dart').absolute;

  group('restrictive class modifier check', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync(
        'elmix-restrictive-modifier-check-',
      );
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    test(
      'passes package and retained prototype source without modifiers',
      () async {
        writeSource(
          fixture,
          'packages/example/lib/example.dart',
          'class Example {}',
        );
        writeSource(
          fixture,
          '.scratch/example/lib/example.dart',
          'abstract class Example {}',
        );

        final result = await Process.run(
          Platform.resolvedExecutable,
          [checker.path, '--root', fixture.path],
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          result.stdout,
          contains('No restrictive Dart class modifiers found.'),
        );
      },
    );

    test('reports banned modifiers in retained prototype source', () async {
      writeSource(
        fixture,
        '.scratch/example/lib/example.dart',
        'sealed class Example {}',
      );

      final result = await Process.run(
        Platform.resolvedExecutable,
        [checker.path, '--root', fixture.path],
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('.scratch/example/lib/example.dart:1'));
      expect(result.stderr, contains('sealed class'));
    });

    test('ignores explanatory comments in package source', () async {
      writeSource(
        fixture,
        'packages/example/lib/example.dart',
        '// A sealed class would be too restrictive here.\nclass Example {}',
      );

      final result = await Process.run(
        Platform.resolvedExecutable,
        [checker.path, '--root', fixture.path],
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
    });
  });
}

void writeSource(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
