import 'dart:io';

import 'package:elmix_engine/elmix_engine.dart';
import 'package:elmix_sqlite/elmix_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('SQLite-backed Engine integration', () {
    test(
      'persists schemas and records through Engine use cases',
      () async {
        final databaseFile = _temporaryDatabaseFile();
        final firstStorage = SqliteStorageAdapter.open(databaseFile.path);
        final firstEngine = ElmixEngine(storage: firstStorage);

        await firstEngine.registerCollection(
          const CollectionSchema.auth(
            name: 'members',
            fields: <SchemaField>[
              SchemaField.recordIdentifier(),
              SchemaField(name: 'email', type: FieldType.email, required: true),
              SchemaField(
                name: 'passwordHash',
                type: FieldType.password,
                required: true,
              ),
              SchemaField(name: 'displayName', type: FieldType.text),
            ],
            accessRules: <CollectionOperation, AccessRule>{},
          ),
        );
        await firstEngine.registerCollection(
          const CollectionSchema(
            name: 'posts',
            fields: <SchemaField>[
              SchemaField.recordIdentifier(),
              SchemaField(name: 'title', type: FieldType.text, required: true),
              SchemaField(name: 'published', type: FieldType.bool),
              SchemaField(
                name: 'author',
                type: FieldType.relation,
                required: true,
                targetCollection: 'members',
              ),
            ],
            accessRules: <CollectionOperation, AccessRule>{},
          ),
        );

        await firstEngine
            .collection('members')
            .create(
              const AuthRecord(
                collection: 'members',
                id: RecordIdentifier('member_1'),
                data: <String, Object?>{
                  'email': 'member@example.com',
                  'passwordHash': 'stored-password-hash',
                  'displayName': 'Member One',
                },
              ),
            );
        await firstEngine
            .collection('posts')
            .create(
              const Record(
                collection: 'posts',
                id: RecordIdentifier('post_1'),
                data: <String, Object?>{
                  'title': 'SQLite-backed Engine',
                  'published': false,
                  'author': 'member_1',
                },
              ),
            );
        firstStorage.close();

        final secondStorage = SqliteStorageAdapter.open(databaseFile.path);
        addTearDown(secondStorage.close);
        final secondEngine = ElmixEngine(storage: secondStorage);

        final membersSchema = await secondEngine.getCollectionSchema('members');
        expect(membersSchema?.isAuthCollection, isTrue);
        expect(
          membersSchema?.fields.map((field) => field.name),
          <String>['id', 'email', 'passwordHash', 'displayName'],
        );

        final postsSchema = await secondEngine.getCollectionSchema('posts');
        final authorField = postsSchema?.fields.firstWhere(
          (field) => field.name == 'author',
        );
        expect(authorField?.type, FieldType.relation);
        expect(authorField?.targetCollection, 'members');

        final posts = secondEngine.collection('posts');
        expect(
          (await posts.get(const RecordIdentifier('post_1')))?.data,
          <String, Object?>{
            'title': 'SQLite-backed Engine',
            'published': false,
            'author': 'member_1',
          },
        );

        await posts.update(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post_1'),
            data: <String, Object?>{
              'title': 'SQLite-backed Engine checkpoint',
              'published': true,
              'author': 'member_1',
            },
          ),
        );

        final listed = await posts.list(
          query: const QueryExpression(
            filters: <QueryFilter>[
              QueryFilter(
                field: 'author',
                operator: QueryOperator.equals,
                value: 'member_1',
              ),
            ],
          ),
        );
        expect(listed.items.map((record) => record.id.value), <String>[
          'post_1',
        ]);
        expect(listed.items.single.data['published'], isTrue);

        await posts.delete(const RecordIdentifier('post_1'));
        expect(await posts.get(const RecordIdentifier('post_1')), isNull);

        final authRecord = await secondEngine
            .collection('members')
            .get(const RecordIdentifier('member_1'));
        expect(authRecord?.data['email'], 'member@example.com');
      },
    );
  });
}

File _temporaryDatabaseFile() {
  final directory = Directory.systemTemp.createTempSync(
    'elmix_engine_sqlite_test_',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  return File('${directory.path}/elmix.db');
}
