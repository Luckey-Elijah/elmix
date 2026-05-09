import 'package:elmix_engine/elmix_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ElmixEngine collection schemas', () {
    test('registers, retrieves, and lists collection schemas', () async {
      final storage = InMemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      const schema = CollectionSchema(
        name: 'posts',
        fields: [
          SchemaField(name: 'title', type: FieldType.text, required: true),
        ],
        accessRules: {},
      );

      await engine.registerCollection(schema);

      expect(await engine.getCollectionSchema('posts'), same(schema));
      expect(await engine.listCollections(), [same(schema)]);
    });

    test('does not replace an existing schema through registration', () async {
      final storage = InMemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      const original = CollectionSchema(
        name: 'posts',
        fields: [
          SchemaField(name: 'title', type: FieldType.text),
        ],
        accessRules: {},
      );
      const replacement = CollectionSchema(
        name: 'posts',
        fields: [
          SchemaField(name: 'body', type: FieldType.text),
        ],
        accessRules: {},
      );

      await engine.registerCollection(original);

      await expectLater(
        engine.registerCollection(replacement),
        throwsA(isA<CollectionSchemaException>()),
      );

      await engine.updateCollectionSchema(replacement);

      expect(await engine.getCollectionSchema('posts'), same(replacement));
    });

    test(
      'treats created and updated as removable default schema fields',
      () async {
        final storage = InMemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        final schemaWithDefaults = CollectionSchema(
          name: 'posts',
          fields: [
            ...CollectionSchema.defaultFields(),
            const SchemaField(name: 'title', type: FieldType.text),
          ],
          accessRules: const {},
        );

        await engine.registerCollection(schemaWithDefaults);

        expect(
          (await engine.getCollectionSchema(
            'posts',
          ))?.fields.map((field) => field.name),
          ['id', 'created', 'updated', 'title'],
        );

        const schemaWithoutDefaults = CollectionSchema(
          name: 'notes',
          fields: [
            SchemaField(name: 'body', type: FieldType.text),
          ],
          accessRules: {},
        );

        await engine.registerCollection(schemaWithoutDefaults);
        await engine
            .collection('notes')
            .create(
              const Record(
                collection: 'notes',
                id: RecordIdentifier('note-1'),
                data: {'body': 'No timestamps required.'},
              ),
            );

        expect(
          (await engine.getCollectionSchema(
            'notes',
          ))?.fields.map((field) => field.name),
          ['body'],
        );
        expect(
          (await engine
                  .collection('notes')
                  .get(
                    const RecordIdentifier('note-1'),
                  ))
              ?.data,
          {'body': 'No timestamps required.'},
        );
      },
    );
  });

  group('ElmixEngine records', () {
    test('creates, lists, views, updates, and deletes records', () async {
      final storage = InMemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      const schema = CollectionSchema(
        name: 'posts',
        fields: [
          SchemaField(name: 'title', type: FieldType.text, required: true),
        ],
        accessRules: {},
      );

      await engine.registerCollection(schema);
      final posts = engine.collection('posts');

      await posts.create(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('post-1'),
          data: {'title': 'First post'},
        ),
      );

      expect((await posts.list()).items.map((record) => record.id.value), [
        'post-1',
      ]);
      expect(await posts.get(const RecordIdentifier('post-1')), isA<Record>());

      await posts.update(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('post-1'),
          data: {'title': 'Edited post'},
        ),
      );

      expect(
        (await posts.get(const RecordIdentifier('post-1')))?.data,
        {'title': 'Edited post'},
      );

      await posts.delete(const RecordIdentifier('post-1'));

      expect(await posts.get(const RecordIdentifier('post-1')), isNull);
      expect((await posts.list()).items, isEmpty);
    });

    test(
      'validates record writes against supported schema field types',
      () async {
        final storage = InMemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);

        await engine.registerCollection(
          const CollectionSchema(
            name: 'profiles',
            fields: [
              SchemaField(name: 'name', type: FieldType.text, required: true),
              SchemaField(name: 'age', type: FieldType.number),
              SchemaField(name: 'verified', type: FieldType.bool),
              SchemaField(name: 'birthday', type: FieldType.date),
              SchemaField(name: 'email', type: FieldType.email),
              SchemaField(name: 'secret', type: FieldType.password),
              SchemaField(name: 'role', type: FieldType.select),
              SchemaField(
                name: 'organization',
                type: FieldType.relation,
                targetCollection: 'organizations',
              ),
              SchemaField(name: 'settings', type: FieldType.json),
            ],
            accessRules: {},
          ),
        );

        await engine
            .collection('profiles')
            .create(
              Record(
                collection: 'profiles',
                id: const RecordIdentifier('profile-1'),
                data: {
                  'name': 'Ada',
                  'age': 37,
                  'verified': true,
                  'birthday': DateTime.utc(1989, 12, 10),
                  'email': 'ada@example.com',
                  'secret': 'hashed-secret',
                  'role': 'admin',
                  'organization': 'org-1',
                  'settings': const {
                    'theme': 'dark',
                    'notifications': ['email'],
                  },
                },
              ),
            );

        await expectLater(
          engine
              .collection('profiles')
              .create(
                const Record(
                  collection: 'profiles',
                  id: RecordIdentifier('profile-2'),
                  data: {'name': 123},
                ),
              ),
          throwsA(isA<RecordValidationException>()),
        );
      },
    );

    test('requires every record to have a non-empty identifier', () async {
      final storage = InMemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);

      await engine.registerCollection(
        const CollectionSchema(
          name: 'posts',
          fields: [
            SchemaField(name: 'title', type: FieldType.text),
          ],
          accessRules: {},
        ),
      );

      await expectLater(
        engine
            .collection('posts')
            .create(
              const Record(
                collection: 'posts',
                id: RecordIdentifier(''),
                data: {'title': 'Untitled'},
              ),
            ),
        throwsA(isA<RecordValidationException>()),
      );
    });
  });
}

class InMemoryStorageAdapter implements StorageAdapter {
  final Map<String, CollectionSchema> _schemas = {};
  final Map<String, Map<String, Record>> _records = {};

  @override
  Future<CollectionSchema?> getCollectionSchema(String name) async {
    return _schemas[name];
  }

  @override
  Future<List<CollectionSchema>> listCollectionSchemas() async {
    return List.unmodifiable(_schemas.values);
  }

  @override
  Future<RecordPage> listRecords({
    required String collection,
    QueryExpression query = const QueryExpression(),
  }) async {
    final items = List<Record>.unmodifiable(
      _records[collection]?.values ?? const <Record>[],
    );
    return RecordPage(
      items: items,
      page: query.pagination.page,
      perPage: query.pagination.perPage,
      totalItems: items.length,
    );
  }

  @override
  Future<Record?> getRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    return _records[collection]?[id.value];
  }

  @override
  Future<void> putCollectionSchema(CollectionSchema schema) async {
    _schemas[schema.name] = schema;
  }

  @override
  Future<void> putRecord(Record record) async {
    _records.putIfAbsent(record.collection, () => {})[record.id.value] = record;
  }

  @override
  Future<void> deleteRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    _records[collection]?.remove(id.value);
  }
}
