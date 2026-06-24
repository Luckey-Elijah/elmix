import 'dart:io';

final _restrictedModifierPattern = RegExp(
  r'^\s*(?:@\w+(?:\.\w+)*(?:\([^)]*\))?\s+)*(abstract\s+(?:final|interface|base)|interface|final|sealed|base)\s+class\b',
);

Future<void> main(List<String> arguments) async {
  final root = _rootDirectory(arguments);
  final violations = <String>[];

  for (final sourceRoot in _sourceRoots(root)) {
    await for (final entity in sourceRoot.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }

      final lines = await entity.readAsLines();
      for (var index = 0; index < lines.length; index++) {
        final match = _restrictedModifierPattern.firstMatch(lines[index]);
        if (match != null) {
          final path = entity.path.substring(root.path.length + 1);
          violations.add('$path:${index + 1}: ${match.group(1)} class');
        }
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('No restrictive Dart class modifiers found.');
    return;
  }

  stderr.writeln('Restrictive Dart class modifiers are not allowed:');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
}

Directory _rootDirectory(List<String> arguments) {
  final rootIndex = arguments.indexOf('--root');
  if (rootIndex == -1) {
    return Directory.current.absolute;
  }

  if (rootIndex == arguments.length - 1) {
    usage('Missing path after --root.');
  }

  return Directory(arguments[rootIndex + 1]).absolute;
}

Never usage(String message) {
  stderr
    ..writeln(message)
    ..writeln(
      'Usage: dart run tool/check_restrictive_class_modifiers.dart [--root <path>]',
    );
  exit(64);
}

Iterable<Directory> _sourceRoots(Directory root) sync* {
  for (final name in ['packages', '.scratch', 'prototype', 'prototypes']) {
    final directory = Directory('${root.path}/$name');
    if (directory.existsSync()) {
      yield directory;
    }
  }
}
