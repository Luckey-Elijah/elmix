import 'dart:io';

Future<void> main(List<String> arguments) async {
  final root = _rootDirectory(arguments);
  final analyzer = await Process.run(
    Platform.resolvedExecutable,
    const <String>['analyze'],
    workingDirectory: root.path,
  );
  _write(analyzer);
  if (analyzer.exitCode != 0) {
    exitCode = analyzer.exitCode;
    return;
  }

  final tests = await Process.run(
    Platform.resolvedExecutable,
    const <String>['test'],
    workingDirectory: root.path,
  );
  _write(tests);
  if (tests.exitCode != 0) {
    exitCode = tests.exitCode;
    return;
  }

  final checker = File.fromUri(
    Platform.script.resolve('check_restrictive_class_modifiers.dart'),
  );
  final modifiers = await Process.run(
    Platform.resolvedExecutable,
    <String>[checker.path, '--root', root.path],
  );
  _write(modifiers);
  if (modifiers.exitCode != 0) {
    exitCode = modifiers.exitCode;
    return;
  }

  stdout.writeln('Workspace verification passed.');
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

void _write(ProcessResult result) {
  stdout.write(result.stdout);
  stderr.write(result.stderr);
}

Never usage(String message) {
  stderr
    ..writeln(message)
    ..writeln('Usage: dart run tool/verify.dart [--root <path>]');
  exit(64);
}
