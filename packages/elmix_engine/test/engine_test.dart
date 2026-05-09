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
      'does not create a record when its identifier already exists',
      () async {
        final storage = InMemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        const schema = CollectionSchema(
          name: 'posts',
          fields: [
            SchemaField(name: 'title', type: FieldType.text),
          ],
          accessRules: {},
        );
        final posts = engine.collection('posts');

        await engine.registerCollection(schema);
        await posts.create(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post-1'),
            data: {'title': 'First post'},
          ),
        );

        await expectLater(
          posts.create(
            const Record(
              collection: 'posts',
              id: RecordIdentifier('post-1'),
              data: {'title': 'Replacement post'},
            ),
          ),
          throwsA(isA<RecordValidationException>()),
        );

        expect(
          (await posts.get(const RecordIdentifier('post-1')))?.data,
          {'title': 'First post'},
        );
      },
    );

    test('allows backing storage to assign identifiers on create', () async {
      final storage = InMemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      const schema = CollectionSchema(
        name: 'posts',
        fields: [
          SchemaField(name: 'title', type: FieldType.text),
        ],
        accessRules: {},
      );

      await engine.registerCollection(schema);

      final created = await engine
          .collection('posts')
          .create(
            const Record(
              collection: 'posts',
              id: RecordIdentifier(''),
              data: {'title': 'Generated id'},
            ),
          );

      expect(created.id.value, isNotEmpty);
      expect(
        (await engine.collection('posts').get(created.id))?.data,
        {'title': 'Generated id'},
      );
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

    test('rejects record writes with undeclared data fields', () async {
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
                id: RecordIdentifier('post-1'),
                data: {
                  'title': 'First post',
                  'published': true,
                },
              ),
            ),
        throwsA(isA<RecordValidationException>()),
      );
    });

    test('requires updates to have a non-empty identifier', () async {
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
            .update(
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
  Future<Record> putRecord(Record record) async {
    final stored = _recordWithStorageIdentifier(record);
    _records.putIfAbsent(stored.collection, () => {})[stored.id.value] = stored;
    return stored;
  }

  @override
  Future<void> deleteRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    _records[collection]?.remove(id.value);
  }

  Record _recordWithStorageIdentifier(Record record) {
    if (record.id.value.trim().isNotEmpty) {
      return record;
    }

    final collectionRecords = _records[record.collection] ?? const {};
    var next = collectionRecords.length + 1;
    var nextId = '${record.collection}-$next';
    while (collectionRecords.containsKey(nextId)) {
      next += 1;
      nextId = '${record.collection}-$next';
    }

    return Record(
      collection: record.collection,
      id: RecordIdentifier(nextId),
      data: record.data,
    );
  }
}
