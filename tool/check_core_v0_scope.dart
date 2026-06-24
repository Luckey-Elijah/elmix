import 'dart:io';

const _initialModuleSet = <String>{
  'packages/elmix_engine',
  'packages/elmix_sqlite',
  'packages/elmix_server',
  'packages/elmix_admin',
  'packages/elmix_client',
  'packages/elmix_cli',
};

Future<void> main(List<String> arguments) async {
  final root = _rootDirectory(arguments);
  final pubspec = File('${root.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    usage('Could not find pubspec.yaml in ${root.path}.');
  }

  final packages = _workspacePackages(await pubspec.readAsLines());
  final unexpected = packages.difference(_initialModuleSet);
  final missing = _initialModuleSet.difference(packages);

  if (unexpected.isEmpty && missing.isEmpty) {
    stdout.writeln('Core v0 workspace scope is valid.');
    return;
  }

  stderr.writeln(
    'The workspace must remain limited to the Initial Module Set.',
  );
  if (unexpected.isNotEmpty) {
    stderr.writeln('Unexpected package(s): ${unexpected.join(', ')}');
  }
  if (missing.isNotEmpty) {
    stderr.writeln('Missing package(s): ${missing.join(', ')}');
  }
  exitCode = 1;
}

Set<String> _workspacePackages(List<String> lines) {
  final workspaceIndex = lines.indexWhere(
    (line) => line.trim() == 'workspace:',
  );
  if (workspaceIndex == -1) {
    return <String>{};
  }

  final packages = <String>{};
  for (final line in lines.skip(workspaceIndex + 1)) {
    final match = RegExp(r'^\s+-\s+(packages/\S+)\s*$').firstMatch(line);
    if (match == null) {
      if (line.trim().isNotEmpty) break;
      continue;
    }
    packages.add(match.group(1)!);
  }
  return packages;
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
    ..writeln('Usage: dart run tool/check_core_v0_scope.dart [--root <path>]');
  exit(64);
}
