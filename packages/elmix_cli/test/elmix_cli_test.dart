import 'dart:io';

import 'package:elmix_cli/elmix_cli.dart';
import 'package:elmix_client/elmix_client.dart';
import 'package:elmix_engine/elmix_engine.dart';
import 'package:elmix_sqlite/elmix_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('elmix create', () {
    test(
      'creates a minimal runnable app and tells the developer next steps',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'elmix_cli_create_test_',
        );
        addTearDown(() => directory.deleteSync(recursive: true));

        final result = await ElmixCommandRunner(
          workingDirectory: directory,
        ).runWithResult(<String>['create', 'journal']);

        expect(result.exitCode, 0);
        expect(result.output, contains('Created Elmix app journal'));
        expect(result.output, contains('cd journal'));
        expect(result.output, contains('elmix serve'));
        expect(
          File('${directory.path}/journal/pubspec.yaml').existsSync(),
          true,
        );
        expect(
          File('${directory.path}/journal/bin/server.dart').existsSync(),
          true,
        );
        expect(File('${directory.path}/journal/elmix.db').existsSync(), false);
      },
    );
  });

  group('elmix schema snapshot', () {
    test('imports and exports collection schemas', () async {
      final directory = Directory.systemTemp.createTempSync(
        'elmix_cli_schema_test_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final snapshot = File('${directory.path}/schema.json')
        ..writeAsStringSync('''
{
  "collections": [
    {
      "name": "posts",
      "isAuthCollection": false,
      "fields": [
        {"name": "id", "type": "text", "required": true, "removable": false, "systemRole": "recordIdentifier"},
        {"name": "title", "type": "text", "required": true, "removable": true, "systemRole": "none"}
      ],
      "accessRules": {}
    }
  ]
}
''');
      final exported = File('${directory.path}/exported-schema.json');
      final runner = ElmixCommandRunner(workingDirectory: directory);

      final importResult = await runner.runWithResult(<String>[
        'schema',
        'import',
        '--db',
        'elmix.db',
        '--file',
        snapshot.path,
      ]);
      final exportResult =
          await ElmixCommandRunner(
            workingDirectory: directory,
          ).runWithResult(<String>[
            'schema',
            'export',
            '--db',
            'elmix.db',
            '--file',
            exported.path,
          ]);

      expect(importResult.exitCode, 0);
      expect(importResult.output, contains('Imported Schema Snapshot'));
      expect(importResult.output, isNot(contains('migration')));
      expect(exportResult.exitCode, 0);
      expect(exportResult.output, contains('Exported Schema Snapshot'));
      expect(exported.readAsStringSync(), contains('"name": "posts"'));
      expect(exported.readAsStringSync(), contains('"title"'));
    });
  });

  group('elmix admin create', () {
    test('creates an Admin Account through the control plane', () async {
      final directory = Directory.systemTemp.createTempSync(
        'elmix_cli_admin_test_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final databasePath = '${directory.path}/elmix.db';

      final result =
          await ElmixCommandRunner(
            workingDirectory: directory,
          ).runWithResult(<String>[
            'admin',
            'create',
            '--db',
            databasePath,
            '--email',
            'admin@example.com',
            '--password',
            'secret-password',
          ]);

      expect(result.exitCode, 0);
      expect(
        result.output,
        contains('Created Admin Account admin@example.com'),
      );

      final storage = SqliteStorageAdapter.open(databasePath);
      addTearDown(storage.close);
      final engine = ElmixEngine(storage: storage);
      final schema = await engine.getCollectionSchema('_admins');
      expect(schema?.isAuthCollection, true);
      final admin = await engine
          .collection('_admins', context: RequestContext.system)
          .get(const RecordIdentifier('admin@example.com'));
      expect(admin?.data['email'], 'admin@example.com');
      expect(admin?.data['passwordHash'], isNot('secret-password'));
      expect(admin?.data['passwordHash'], startsWith(r'pbkdf2-sha256$'));
      await expectLater(
        engine
            .collection('_admins')
            .get(const RecordIdentifier('admin@example.com')),
        throwsA(isA<AuthorizationException>()),
      );
    });

    test('stores salted password hashes for Admin Accounts', () async {
      final directory = Directory.systemTemp.createTempSync(
        'elmix_cli_admin_hash_test_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final databasePath = '${directory.path}/elmix.db';
      final runner = ElmixCommandRunner(workingDirectory: directory);

      await runner.runWithResult(<String>[
        'admin',
        'create',
        '--db',
        databasePath,
        '--email',
        'first@example.com',
        '--password',
        'same-password',
      ]);
      await runner.runWithResult(<String>[
        'admin',
        'create',
        '--db',
        databasePath,
        '--email',
        'second@example.com',
        '--password',
        'same-password',
      ]);

      final storage = SqliteStorageAdapter.open(databasePath);
      addTearDown(storage.close);
      final engine = ElmixEngine(storage: storage);
      final admins = engine.collection(
        '_admins',
        context: RequestContext.system,
      );
      final first = await admins.get(
        const RecordIdentifier('first@example.com'),
      );
      final second = await admins.get(
        const RecordIdentifier('second@example.com'),
      );

      expect(first?.data['passwordHash'], startsWith(r'pbkdf2-sha256$'));
      expect(second?.data['passwordHash'], startsWith(r'pbkdf2-sha256$'));
      expect(first?.data['passwordHash'], isNot(second?.data['passwordHash']));
    });
  });

  group('elmix serve', () {
    test('starts an Elmix server backed by SQLite', () async {
      final directory = Directory.systemTemp.createTempSync(
        'elmix_cli_serve_test_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final databasePath = '${directory.path}/elmix.db';

      final result =
          await ElmixCommandRunner(
            workingDirectory: directory,
          ).runWithResult(<String>[
            'serve',
            '--db',
            databasePath,
            '--port',
            '0',
            '--exit-after-start',
          ]);

      expect(result.exitCode, 0);
      expect(result.output, contains('Serving Elmix'));
      expect(result.output, contains(databasePath));
      expect(File(databasePath).existsSync(), true);
    });

    test('serves a SQLite-backed app consumed by the Dynamic Client', () async {
      final directory = Directory.systemTemp.createTempSync(
        'elmix_cli_dynamic_client_test_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final databasePath = '${directory.path}/elmix.db';
      final snapshot = File('${directory.path}/schema.json')
        ..writeAsStringSync(r'''
{
  "collections": [
    {
      "name": "users",
      "isAuthCollection": true,
      "fields": [
        {"name": "id", "type": "text", "required": true, "removable": false, "systemRole": "recordIdentifier"},
        {"name": "email", "type": "email", "required": true, "removable": true, "systemRole": "none"},
        {"name": "password", "type": "password", "required": true, "removable": true, "systemRole": "none"}
      ],
      "accessRules": {"create": "true", "view": "auth.id == record.id"}
    },
    {
      "name": "posts",
      "isAuthCollection": false,
      "fields": [
        {"name": "id", "type": "text", "required": true, "removable": false, "systemRole": "recordIdentifier"},
        {"name": "title", "type": "text", "required": true, "removable": true, "systemRole": "none"},
        {"name": "published", "type": "bool", "required": true, "removable": true, "systemRole": "none"}
      ],
      "accessRules": {
        "list": "true",
        "view": "true",
        "create": "auth.collection == \"users\"",
        "update": "auth.collection == \"users\"",
        "delete": "false"
      }
    }
  ]
}
''');

      final runner = ElmixCommandRunner(workingDirectory: directory);
      final importResult = await runner.runWithResult(<String>[
        'schema',
        'import',
        '--db',
        databasePath,
        '--file',
        snapshot.path,
      ]);
      expect(importResult.exitCode, 0);

      final served = await runner.startServe(<String>[
        '--db',
        databasePath,
        '--port',
        '0',
      ]);
      addTearDown(served.close);

      final client = ElmixClient(served.url);
      final users = client.collection('users');
      final posts = client.collection('posts');

      final user = await users.create(<String, Object?>{
        'id': 'author-1',
        'data': <String, Object?>{
          'email': 'author@example.com',
          'password': 'secret-password',
        },
      });
      expect(user.id, 'author-1');

      final auth = await users.authWithPassword(
        email: 'author@example.com',
        password: 'secret-password',
      );
      expect(auth.record.id, 'author-1');
      expect(client.bearerToken, auth.token);

      final created = await posts.create(<String, Object?>{
        'id': 'post-1',
        'data': <String, Object?>{
          'title': 'First CLI-served post',
          'published': false,
        },
      });
      expect(created.data['title'], 'First CLI-served post');

      final page = await posts.list();
      expect(page.items.map((record) => record.id), contains('post-1'));

      final viewed = await posts.view('post-1');
      expect(viewed.data['published'], false);

      final updated = await posts.update('post-1', <String, Object?>{
        'data': <String, Object?>{'published': true},
      });
      expect(updated.data['published'], true);

      await expectLater(
        posts.delete('post-1'),
        throwsA(
          isA<ElmixClientException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having((error) => error.code, 'code', 'forbidden'),
        ),
      );
    });
  });
}
