import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart' as args;
import 'package:elmix_admin/elmix_admin.dart';
import 'package:elmix_engine/elmix_engine.dart';
import 'package:elmix_server/elmix_server.dart';
import 'package:elmix_sqlite/elmix_sqlite.dart';
import 'package:mason_logger/mason_logger.dart';

/// Result of running the Elmix CLI from tests or embedding code.
class ElmixCommandResult {
  /// Creates a command result.
  const ElmixCommandResult({
    required this.exitCode,
    required this.output,
  });

  /// Process exit code.
  final int exitCode;

  /// User-visible output emitted by the command.
  final String output;
}

/// Elmix command-line entrypoint.
class ElmixCommandRunner {
  /// Creates a command runner for the Elmix CLI.
  ElmixCommandRunner({
    Directory? workingDirectory,
    Logger? logger,
  }) : _workingDirectory = workingDirectory ?? Directory.current,
       _logger = logger ?? Logger(),
       _output = StringBuffer() {
    _runner = args.CommandRunner<int>('elmix', 'Elmix Core v0 CLI.')
      ..addCommand(_CreateCommand(this))
      ..addCommand(_AdminCommand(this))
      ..addCommand(_SchemaCommand(this))
      ..addCommand(_ServeCommand(this));
  }

  final Directory _workingDirectory;
  final Logger _logger;
  StringBuffer _output;
  late final args.CommandRunner<int> _runner;

  /// Returns the command-line usage text.
  String usage() => _runner.usage;

  /// Runs the CLI and returns its process exit code.
  Future<int> run(List<String> arguments) async {
    final result = await runWithResult(arguments);
    return result.exitCode;
  }

  /// Runs the CLI and returns its exit code plus captured user output.
  Future<ElmixCommandResult> runWithResult(List<String> arguments) async {
    _output = StringBuffer();
    try {
      final exitCode = await _runner.run(arguments) ?? ExitCode.success.code;
      return ElmixCommandResult(exitCode: exitCode, output: _output.toString());
    } on args.UsageException catch (error) {
      _err(error.message);
      _info('');
      _info(error.usage);
      return ElmixCommandResult(
        exitCode: ExitCode.usage.code,
        output: _output.toString(),
      );
    } on Exception catch (error) {
      _err(error.toString());
      return ElmixCommandResult(
        exitCode: ExitCode.software.code,
        output: _output.toString(),
      );
    }
  }

  void _info(String message) {
    _output.writeln(message);
    _logger.info(message);
  }

  void _success(String message) {
    _output.writeln(message);
    _logger.success(message);
  }

  void _err(String message) {
    _output.writeln(message);
    _logger.err(message);
  }
}

class _ServeCommand extends args.Command<int> {
  _ServeCommand(this._elmix) {
    argParser
      ..addOption(
        'db',
        defaultsTo: 'elmix.db',
        help: 'Path to the SQLite database.',
      )
      ..addOption('host', defaultsTo: '127.0.0.1', help: 'Host to bind.')
      ..addOption('port', defaultsTo: '8080', help: 'Port to bind.')
      ..addFlag(
        'exit-after-start',
        hide: true,
        help: 'Close the server immediately after it starts.',
      );
  }

  final ElmixCommandRunner _elmix;

  @override
  String get description => 'Starts an Elmix server backed by SQLite.';

  @override
  String get name => 'serve';

  @override
  Future<int> run() async {
    final databasePath = _resolveCliPath(
      _elmix._workingDirectory,
      argResults!['db']! as String,
    );
    final host = argResults!['host']! as String;
    final port = int.parse(argResults!['port']! as String);
    final storage = SqliteStorageAdapter.open(databasePath);
    final engine = ElmixEngine(storage: storage);
    final server = ElmixServer(engine);
    final httpServer = await HttpServer.bind(host, port);

    _elmix
      .._success(
        'Serving Elmix at http://${httpServer.address.host}:${httpServer.port}.',
      )
      .._info('SQLite database: $databasePath');

    if (argResults!['exit-after-start'] == true) {
      await httpServer.close(force: true);
      storage.close();
      return ExitCode.success.code;
    }

    unawaited(_handleRequests(httpServer, server));
    await Completer<void>().future;
    return ExitCode.success.code;
  }

  Future<void> _handleRequests(
    HttpServer httpServer,
    ElmixServer server,
  ) async {
    await for (final request in httpServer) {
      await _handleRequest(request, server);
    }
  }

  Future<void> _handleRequest(
    HttpRequest request,
    ElmixServer server,
  ) async {
    final body = await utf8.decoder.bind(request).join();
    final response = await server.handle(
      ElmixHttpRequest(
        method: _methodFrom(request.method),
        path: request.uri.path,
        headers: _headersFrom(request.headers),
        body: body.trim().isEmpty ? null : jsonDecode(body),
      ),
    );
    request.response.statusCode = response.statusCode;
    if (response.body != null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response.body));
    }
    await request.response.close();
  }

  Map<String, String> _headersFrom(HttpHeaders headers) {
    final result = <String, String>{};
    headers.forEach((name, values) {
      result[name] = values.join(',');
    });
    return result;
  }

  ElmixHttpRequestMethod _methodFrom(String method) {
    return ElmixHttpRequestMethod.values.firstWhere(
      (candidate) => candidate.value == method,
    );
  }
}

class _AdminCommand extends args.Command<int> {
  _AdminCommand(ElmixCommandRunner elmix) {
    addSubcommand(_AdminCreateCommand(elmix));
  }

  @override
  String get description => 'Manages Elmix Admin Accounts.';

  @override
  String get name => 'admin';
}

class _AdminCreateCommand extends args.Command<int> {
  _AdminCreateCommand(this._elmix) {
    argParser
      ..addOption(
        'db',
        defaultsTo: 'elmix.db',
        help: 'Path to the SQLite database.',
      )
      ..addOption('email', mandatory: true, help: 'Admin email address.')
      ..addOption('password', mandatory: true, help: 'Admin password.');
  }

  final ElmixCommandRunner _elmix;

  @override
  String get description => 'Creates an Admin Account.';

  @override
  String get name => 'create';

  @override
  Future<int> run() async {
    final databasePath = _resolveCliPath(
      _elmix._workingDirectory,
      argResults!['db']! as String,
    );
    final email = argResults!['email']! as String;
    final password = argResults!['password']! as String;
    final storage = SqliteStorageAdapter.open(databasePath);
    try {
      final engine = ElmixEngine(storage: storage);
      final controlPlane = AdminControlPlane(engine);
      await controlPlane.createAdminAccount(email: email, password: password);
      _elmix._success('Created Admin Account $email.');
      return ExitCode.success.code;
    } finally {
      storage.close();
    }
  }
}

class _SchemaCommand extends args.Command<int> {
  _SchemaCommand(ElmixCommandRunner elmix) {
    addSubcommand(_SchemaExportCommand(elmix));
    addSubcommand(_SchemaImportCommand(elmix));
  }

  @override
  String get description => 'Imports and exports Schema Snapshots.';

  @override
  String get name => 'schema';
}

abstract class _SchemaSnapshotCommand extends args.Command<int> {
  _SchemaSnapshotCommand(this._elmix) {
    argParser
      ..addOption(
        'db',
        defaultsTo: 'elmix.db',
        help: 'Path to the SQLite database.',
      )
      ..addOption(
        'file',
        abbr: 'f',
        defaultsTo: 'schema.json',
        help: 'Path to the Schema Snapshot JSON file.',
      );
  }

  final ElmixCommandRunner _elmix;

  String get databasePath => _resolvePath(argResults!['db']! as String);

  String get filePath => _resolvePath(argResults!['file']! as String);

  String _resolvePath(String path) {
    return _resolveCliPath(_elmix._workingDirectory, path);
  }
}

class _SchemaExportCommand extends _SchemaSnapshotCommand {
  _SchemaExportCommand(super._elmix);

  @override
  String get description => 'Writes a Schema Snapshot of Collection Schemas.';

  @override
  String get name => 'export';

  @override
  Future<int> run() async {
    final storage = SqliteStorageAdapter.open(databasePath);
    try {
      final engine = ElmixEngine(storage: storage);
      final schemas = await engine.listCollections();
      final snapshot = jsonEncode(
        <String, Object?>{
          'collections': schemas.map(_schemaToJson).toList(),
        },
      );
      File(filePath).writeAsStringSync(_prettyJson(snapshot));
      _elmix
        .._success(
          'Exported Schema Snapshot with ${schemas.length} collection(s).',
        )
        .._info('Wrote $filePath.');
      return ExitCode.success.code;
    } finally {
      storage.close();
    }
  }
}

class _SchemaImportCommand extends _SchemaSnapshotCommand {
  _SchemaImportCommand(super._elmix);

  @override
  String get description => 'Applies a Schema Snapshot to the SQLite database.';

  @override
  String get name => 'import';

  @override
  Future<int> run() async {
    final body = jsonDecode(File(filePath).readAsStringSync());
    final object = body is Map<String, Object?> ? body : <String, Object?>{};
    final collections = object['collections'];
    final schemas = collections is List<Object?>
        ? collections.map(_schemaFromJson).toList()
        : const <CollectionSchema>[];
    final storage = SqliteStorageAdapter.open(databasePath);
    try {
      final engine = ElmixEngine(storage: storage);
      for (final schema in schemas) {
        final existing = await engine.getCollectionSchema(schema.name);
        if (existing == null) {
          await engine.registerCollection(schema);
        } else {
          await engine.updateCollectionSchema(schema);
        }
      }
      _elmix._success(
        'Imported Schema Snapshot with ${schemas.length} collection(s).',
      );
      return ExitCode.success.code;
    } finally {
      storage.close();
    }
  }
}

class _CreateCommand extends args.Command<int> {
  _CreateCommand(this._elmix);

  final ElmixCommandRunner _elmix;

  @override
  String get description => 'Creates a minimal runnable Elmix app.';

  @override
  String get name => 'create';

  @override
  String get invocation => 'elmix create <app>';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.length != 1) {
      throw args.UsageException('Expected one app name.', usage);
    }

    final appName = rest.single;
    final appDirectory = Directory('${_elmix._workingDirectory.path}/$appName');
    if (appDirectory.existsSync()) {
      throw Exception('Directory "$appName" already exists.');
    }

    appDirectory.createSync(recursive: true);
    Directory('${appDirectory.path}/bin').createSync();
    File('${appDirectory.path}/pubspec.yaml').writeAsStringSync(
      _pubspec(appName),
    );
    File('${appDirectory.path}/bin/server.dart').writeAsStringSync(
      _serverEntrypoint(),
    );

    _elmix
      .._success('Created Elmix app $appName.')
      .._info('')
      .._info('Next steps:')
      .._info('  cd $appName')
      .._info('  elmix serve');
    return ExitCode.success.code;
  }

  String _pubspec(String appName) {
    return '''
name: $appName
publish_to: none
environment:
  sdk: ^3.11.0

dependencies:
  elmix_engine: 0.1.0-dev
  elmix_server: 0.1.0-dev
  elmix_sqlite: 0.1.0-dev
''';
  }

  String _serverEntrypoint() {
    return '''
import 'package:elmix_engine/elmix_engine.dart';
import 'package:elmix_sqlite/elmix_sqlite.dart';

Future<void> main() async {
  final storage = SqliteStorageAdapter.open('elmix.db');
  final engine = ElmixEngine(storage: storage);

  await engine.registerCollection(
    CollectionSchema(
      name: 'notes',
      fields: [
        ...CollectionSchema.defaultFields(),
        const SchemaField(name: 'title', type: FieldType.text, required: true),
      ],
      accessRules: const {},
    ),
  );
}
''';
  }
}

String _prettyJson(String compactJson) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(jsonDecode(compactJson))}\n';
}

String _resolveCliPath(Directory workingDirectory, String path) {
  if (path.startsWith('/')) {
    return path;
  }
  return '${workingDirectory.path}/$path';
}

Map<String, Object?> _schemaToJson(CollectionSchema schema) {
  return <String, Object?>{
    'name': schema.name,
    'isAuthCollection': schema.isAuthCollection,
    'fields': schema.fields.map(_fieldToJson).toList(),
    'accessRules': <String, Object?>{
      for (final entry in schema.accessRules.entries)
        entry.key.name: entry.value.expression,
    },
  };
}

Map<String, Object?> _fieldToJson(SchemaField field) {
  return <String, Object?>{
    'name': field.name,
    'type': field.type.name,
    'required': field.required,
    'removable': field.removable,
    'systemRole': field.systemRole.name,
    if (field.targetCollection != null)
      'targetCollection': field.targetCollection,
  };
}

CollectionSchema _schemaFromJson(Object? body) {
  final object = body is Map<String, Object?> ? body : <String, Object?>{};
  final fields = object['fields'];
  final accessRules = object['accessRules'];
  return CollectionSchema(
    name: object['name']! as String,
    isAuthCollection: object['isAuthCollection'] == true,
    fields: fields is List<Object?>
        ? fields.map(_fieldFromJson).toList()
        : const <SchemaField>[],
    accessRules: accessRules is Map<String, Object?>
        ? <CollectionOperation, AccessRule>{
            for (final entry in accessRules.entries)
              _collectionOperation(entry.key): AccessRule(
                entry.value is String ? entry.value! as String : '',
              ),
          }
        : const <CollectionOperation, AccessRule>{},
  );
}

SchemaField _fieldFromJson(Object? body) {
  final object = body is Map<String, Object?> ? body : <String, Object?>{};
  final removable = object['removable'];
  final systemRole = object['systemRole'];
  return SchemaField(
    name: object['name']! as String,
    type: _fieldType(object['type']! as String),
    required: object['required'] == true,
    removable: removable is! bool || removable,
    systemRole: systemRole is String ? _fieldSystemRole(systemRole) : .none,
    targetCollection: object['targetCollection'] as String?,
  );
}

FieldType _fieldType(String name) {
  return FieldType.values.firstWhere((type) => type.name == name);
}

FieldSystemRole _fieldSystemRole(String name) {
  return FieldSystemRole.values.firstWhere((role) => role.name == name);
}

CollectionOperation _collectionOperation(String name) {
  return CollectionOperation.values.firstWhere(
    (operation) => operation.name == name,
  );
}
