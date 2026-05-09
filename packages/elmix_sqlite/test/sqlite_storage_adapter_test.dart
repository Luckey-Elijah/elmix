import 'dart:io';

import 'package:elmix_engine/elmix_engine.dart';
import 'package:elmix_sqlite/elmix_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('SqliteStorageAdapter', () {
    test(
      'persists collection schemas across reopened SQLite databases',
      () async {
        final databaseFile = _temporaryDatabaseFile();
        final firstStorage = SqliteStorageAdapter.open(databaseFile.path);
        final firstEngine = ElmixEngine(storage: firstStorage);
        const schema = CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: FieldType.text, required: true),
            SchemaField(
              name: 'author',
              type: FieldType.relation,
              targetCollection: 'users',
            ),
          ],
          accessRules: <CollectionOperation, AccessRule>{
            CollectionOperation.list: AccessRule('true'),
          },
        );

        await firstEngine.registerCollection(schema);
        firstStorage.close();

        final secondStorage = SqliteStorageAdapter.open(databaseFile.path);
        addTearDown(secondStorage.close);
        final secondEngine = ElmixEngine(storage: secondStorage);

        final loaded = await secondEngine.getCollectionSchema('posts');

        expect(loaded?.name, 'posts');
        expect(loaded?.fields.map((field) => field.name), <String>[
          'id',
          'title',
          'author',
        ]);
        expect(
          loaded?.fields.firstWhere((field) => field.name == 'author').type,
          FieldType.relation,
        );
        expect(
          loaded?.fields
              .firstWhere((field) => field.name == 'author')
              .targetCollection,
          'users',
        );
        expect(
          loaded?.accessRules[CollectionOperation.list]?.expression,
          'true',
        );
      },
    );

    test('lists persisted collection schemas by name', () async {
      final storage = SqliteStorageAdapter();
      addTearDown(storage.close);

      await storage.putCollectionSchema(
        _schemaWithName(
          'posts',
          const <SchemaField>[
            SchemaField(name: 'title', type: FieldType.text),
          ],
        ),
      );
      await storage.putCollectionSchema(
        _schemaWithName(
          'members',
          const <SchemaField>[
            SchemaField(name: 'email', type: FieldType.email),
          ],
        ),
      );

      final schemas = await storage.listCollectionSchemas();

      expect(schemas.map((schema) => schema.name), <String>[
        'members',
        'posts',
      ]);
      expect(
        schemas
            .firstWhere((schema) => schema.name == 'members')
            .fields
            .map((field) => field.name),
        <String>['id', 'email'],
      );
      expect(
        schemas
            .firstWhere((schema) => schema.name == 'posts')
            .fields
            .map((field) => field.name),
        <String>['id', 'title'],
      );
    });

    test(
      'stores and retrieves schema-backed records across reopened databases',
      () async {
        final databaseFile = _temporaryDatabaseFile();
        final firstStorage = SqliteStorageAdapter.open(databaseFile.path);
        final firstEngine = ElmixEngine(storage: firstStorage);
        final publishedAt = DateTime.utc(2026, 5, 9, 12, 30);
        const postsSchema = CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: FieldType.text, required: true),
            SchemaField(name: 'views', type: FieldType.number),
            SchemaField(name: 'published', type: FieldType.bool),
            SchemaField(name: 'publishedAt', type: FieldType.date),
            SchemaField(name: 'authorEmail', type: FieldType.email),
            SchemaField(name: 'status', type: FieldType.select),
            SchemaField(
              name: 'author',
              type: FieldType.relation,
              targetCollection: 'users',
            ),
            SchemaField(name: 'metadata', type: FieldType.json),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        );

        await firstEngine.registerCollection(postsSchema);
        await firstEngine
            .collection('posts')
            .create(
              Record(
                collection: 'posts',
                id: const RecordIdentifier('post_1'),
                data: <String, Object?>{
                  'title': 'SQLite arrives',
                  'views': 42,
                  'published': true,
                  'publishedAt': publishedAt,
                  'authorEmail': 'author@example.com',
                  'status': 'published',
                  'author': 'user_1',
                  'metadata': <String, Object?>{
                    'tags': <Object?>['sqlite', 'storage'],
                  },
                },
              ),
            );
        firstStorage.close();

        final secondStorage = SqliteStorageAdapter.open(databaseFile.path);
        addTearDown(secondStorage.close);
        final secondEngine = ElmixEngine(storage: secondStorage);

        final record = await secondEngine
            .collection('posts')
            .get(const RecordIdentifier('post_1'));

        expect(record?.data, <String, Object?>{
          'title': 'SQLite arrives',
          'views': 42,
          'published': true,
          'publishedAt': publishedAt,
          'authorEmail': 'author@example.com',
          'status': 'published',
          'author': 'user_1',
          'metadata': <String, Object?>{
            'tags': <Object?>['sqlite', 'storage'],
          },
        });
      },
    );

    test(
      'applies added schema fields before updating and listing records',
      () async {
        final storage = SqliteStorageAdapter();
        addTearDown(storage.close);
        final engine = ElmixEngine(storage: storage);
        const initialSchema = CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: FieldType.text, required: true),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        );
        const expandedSchema = CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: FieldType.text, required: true),
            SchemaField(name: 'published', type: FieldType.bool),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        );

        await engine.registerCollection(initialSchema);
        await engine
            .collection('posts')
            .create(
              const Record(
                collection: 'posts',
                id: RecordIdentifier('post_1'),
                data: <String, Object?>{'title': 'Draft'},
              ),
            );
        await engine.updateCollectionSchema(expandedSchema);
        await engine
            .collection('posts')
            .update(
              const Record(
                collection: 'posts',
                id: RecordIdentifier('post_1'),
                data: <String, Object?>{
                  'title': 'Published',
                  'published': true,
                },
              ),
            );

        final page = await engine
            .collection('posts')
            .list(
              query: const QueryExpression(
                filters: <QueryFilter>[
                  QueryFilter(
                    field: 'published',
                    operator: QueryOperator.equals,
                    value: true,
                  ),
                ],
              ),
            );

        expect(page.items.single.data['title'], 'Published');

        await engine
            .collection('posts')
            .delete(
              const RecordIdentifier('post_1'),
            );

        expect(
          await engine
              .collection('posts')
              .get(const RecordIdentifier('post_1')),
          isNull,
        );
      },
    );

    test('applies query filters and sorting when listing records', () async {
      final storage = SqliteStorageAdapter();
      await storage.putCollectionSchema(
        _postsSchemaWithFields(<SchemaField>[
          const SchemaField(name: 'published', type: FieldType.bool),
          const SchemaField(name: 'score', type: FieldType.number),
        ]),
      );

      await storage.putRecord(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('draft_high'),
          data: <String, Object?>{'published': false, 'score': 100},
        ),
      );
      await storage.putRecord(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('published_low'),
          data: <String, Object?>{'published': true, 'score': 10},
        ),
      );
      await storage.putRecord(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('published_high'),
          data: <String, Object?>{'published': true, 'score': 20},
        ),
      );

      final page = await storage.listRecords(
        collection: 'posts',
        query: const QueryExpression(
          filters: <QueryFilter>[
            QueryFilter(
              field: 'published',
              operator: QueryOperator.equals,
              value: true,
            ),
          ],
          sort: <QuerySort>[
            QuerySort(field: 'score', direction: SortDirection.descending),
          ],
        ),
      );

      expect(
        page.items.map((record) => record.id.value),
        <String>['published_high', 'published_low'],
      );
      expect(page.totalItems, 2);
    });

    test(
      'filters by built-in id without requiring duplicated record data',
      () async {
        final storage = SqliteStorageAdapter();
        await storage.putCollectionSchema(
          _postsSchemaWithFields(<SchemaField>[
            const SchemaField(name: 'title', type: FieldType.text),
          ]),
        );

        await storage.putRecord(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post_1'),
            data: <String, Object?>{'title': 'First'},
          ),
        );
        await storage.putRecord(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post_2'),
            data: <String, Object?>{'title': 'Second'},
          ),
        );

        final record = await storage.getRecord(
          collection: 'posts',
          id: const RecordIdentifier('post_2'),
        );
        final page = await storage.listRecords(
          collection: 'posts',
          query: const QueryExpression(
            filters: <QueryFilter>[
              QueryFilter(
                field: 'id',
                operator: QueryOperator.equals,
                value: 'post_2',
              ),
            ],
          ),
        );

        expect(record?.id.value, 'post_2');
        expect(page.items.map((record) => record.id.value), <String>['post_2']);
        expect(page.totalItems, 1);
      },
    );

    test('excludes missing values from range filters', () async {
      final storage = SqliteStorageAdapter();
      await storage.putCollectionSchema(
        _postsSchemaWithFields(<SchemaField>[
          const SchemaField(name: 'title', type: FieldType.text),
          const SchemaField(name: 'score', type: FieldType.number),
        ]),
      );

      await storage.putRecord(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('missing_score'),
          data: <String, Object?>{'title': 'Missing score'},
        ),
      );
      await storage.putRecord(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('null_score'),
          data: <String, Object?>{'score': null},
        ),
      );
      await storage.putRecord(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('low_score'),
          data: <String, Object?>{'score': 5},
        ),
      );
      await storage.putRecord(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('high_score'),
          data: <String, Object?>{'score': 20},
        ),
      );

      final page = await storage.listRecords(
        collection: 'posts',
        query: const QueryExpression(
          filters: <QueryFilter>[
            QueryFilter(
              field: 'score',
              operator: QueryOperator.greaterThan,
              value: 10,
            ),
          ],
        ),
      );

      expect(page.items.map((record) => record.id.value), <String>[
        'high_score',
      ]);
      expect(page.totalItems, 1);
    });
  });
}

File _temporaryDatabaseFile() {
  final directory = Directory.systemTemp.createTempSync('elmix_sqlite_test_');
  addTearDown(() => directory.deleteSync(recursive: true));
  return File('${directory.path}/elmix.db');
}

CollectionSchema _postsSchemaWithFields(List<SchemaField> fields) {
  return _schemaWithName('posts', fields);
}

CollectionSchema _schemaWithName(String name, List<SchemaField> fields) {
  return CollectionSchema(
    name: name,
    fields: <SchemaField>[
      const SchemaField.recordIdentifier(),
      ...fields,
    ],
    accessRules: const <CollectionOperation, AccessRule>{},
  );
}
