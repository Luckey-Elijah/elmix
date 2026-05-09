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
    test(
      'authorizes collection requests with auth records from any auth '
      'collection',
      () async {
        final storage = InMemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        await engine.registerCollection(
          const CollectionSchema.auth(
            name: 'members',
            fields: [
              SchemaField(name: 'email', type: FieldType.email),
            ],
            accessRules: {},
          ),
        );
        await engine.registerCollection(
          const CollectionSchema(
            name: 'posts',
            fields: [
              SchemaField(name: 'title', type: FieldType.text),
            ],
            accessRules: {
              CollectionOperation.list: AccessRule(
                'auth.collection == "members" && auth.id == "member-1"',
              ),
            },
          ),
        );
        await engine
            .collection('posts')
            .create(
              const Record(
                collection: 'posts',
                id: RecordIdentifier('post-1'),
                data: {'title': 'Member post'},
              ),
            );

        final page = await engine
            .collection(
              'posts',
              context: const RequestContext(
                authRecord: AuthRecordIdentity(
                  collection: 'members',
                  id: RecordIdentifier('member-1'),
                ),
              ),
            )
            .list();

        expect(page.items.map((record) => record.id.value), ['post-1']);
      },
    );

    test(
      'evaluates access rules before collection hooks for all operations',
      () async {
        final storage = InMemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        final hook = RecordingActionHook();
        engine.addHook(hook);
        await engine.registerCollection(
          const CollectionSchema(
            name: 'posts',
            fields: [
              SchemaField(name: 'title', type: FieldType.text),
              SchemaField(name: 'views', type: FieldType.number),
            ],
            accessRules: {
              CollectionOperation.list: AccessRule('true'),
              CollectionOperation.view: AccessRule('record.id == "post-1"'),
              CollectionOperation.create: AccessRule(
                'request.data.title == "Allowed"',
              ),
              CollectionOperation.update: AccessRule(
                'record.data.views >= 10 && auth.id != ""',
              ),
              CollectionOperation.delete: AccessRule(
                'auth.collection == "members" && '
                'record.data.title != "Protected"',
              ),
            },
          ),
        );
        final posts = engine.collection(
          'posts',
          context: const RequestContext(
            authRecord: AuthRecordIdentity(
              collection: 'members',
              id: RecordIdentifier('member-1'),
            ),
          ),
        );

        await posts.create(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post-1'),
            data: {'title': 'Allowed', 'views': 10},
          ),
        );
        expect(
          await posts.get(const RecordIdentifier('post-1')),
          isA<Record>(),
        );
        await posts.update(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post-1'),
            data: {'title': 'Allowed', 'views': 12},
          ),
        );
        expect((await posts.list()).items.map((record) => record.id.value), [
          'post-1',
        ]);

        final hookCountBeforeDeniedRequest = hook.contexts.length;
        await expectLater(
          posts.create(
            const Record(
              collection: 'posts',
              id: RecordIdentifier('post-2'),
              data: {'title': 'Denied', 'views': 99},
            ),
          ),
          throwsA(isA<AuthorizationException>()),
        );
        expect(hook.contexts, hasLength(hookCountBeforeDeniedRequest));

        await posts.delete(const RecordIdentifier('post-1'));
        expect(
          await storage.getRecord(
            collection: 'posts',
            id: const RecordIdentifier('post-1'),
          ),
          isNull,
        );
      },
    );

    test('authorizes new saves with create access rules', () async {
      final storage = InMemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      await engine.registerCollection(
        const CollectionSchema(
          name: 'posts',
          fields: [
            SchemaField(name: 'title', type: FieldType.text),
          ],
          accessRules: {
            CollectionOperation.create: AccessRule('false'),
            CollectionOperation.update: AccessRule('true'),
          },
        ),
      );

      await expectLater(
        engine
            .collection('posts')
            .save(
              const Record(
                collection: 'posts',
                id: RecordIdentifier('post-1'),
                data: {'title': 'Bypass attempt'},
              ),
            ),
        throwsA(isA<AuthorizationException>()),
      );

      expect(
        await storage.getRecord(
          collection: 'posts',
          id: const RecordIdentifier('post-1'),
        ),
        isNull,
      );
    });

    test('authorizes updates against stored record data', () async {
      final storage = InMemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      await engine.registerCollection(
        const CollectionSchema(
          name: 'posts',
          fields: [
            SchemaField(name: 'owner', type: FieldType.text),
            SchemaField(name: 'title', type: FieldType.text),
          ],
          accessRules: {
            CollectionOperation.create: AccessRule('true'),
            CollectionOperation.update: AccessRule(
              'record.data.owner == auth.id',
            ),
          },
        ),
      );
      final posts = engine.collection(
        'posts',
        context: const RequestContext(
          authRecord: AuthRecordIdentity(
            collection: 'members',
            id: RecordIdentifier('member-1'),
          ),
        ),
      );
      await posts.create(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('post-1'),
          data: {'owner': 'member-2', 'title': 'Original'},
        ),
      );

      await expectLater(
        posts.update(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post-1'),
            data: {'owner': 'member-1', 'title': 'Spoofed'},
          ),
        ),
        throwsA(isA<AuthorizationException>()),
      );

      expect(
        (await posts.get(const RecordIdentifier('post-1')))?.data,
        {'owner': 'member-2', 'title': 'Original'},
      );
    });

    test(
      'runs collection hooks around authorized collection operations',
      () async {
        final storage = InMemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        final hook = RecordingActionHook();
        engine.addHook(hook);
        await engine.registerCollection(
          const CollectionSchema(
            name: 'posts',
            fields: [
              SchemaField(name: 'title', type: FieldType.text),
            ],
            accessRules: {
              CollectionOperation.create: AccessRule('auth.id == "member-1"'),
            },
          ),
        );

        await engine
            .collection(
              'posts',
              context: const RequestContext(
                authRecord: AuthRecordIdentity(
                  collection: 'members',
                  id: RecordIdentifier('member-1'),
                ),
              ),
            )
            .create(
              const Record(
                collection: 'posts',
                id: RecordIdentifier('post-1'),
                data: {'title': 'Hooked'},
              ),
            );

        expect(
          hook.contexts.map(
            (context) => (
              context.collection,
              context.operation,
              context.phase,
              context.record?.id.value,
              context.authRecord?.collection,
              context.authRecord?.id.value,
            ),
          ),
          [
            (
              'posts',
              CollectionOperation.create,
              HookPhase.before,
              'post-1',
              'members',
              'member-1',
            ),
            (
              'posts',
              CollectionOperation.create,
              HookPhase.after,
              'post-1',
              'members',
              'member-1',
            ),
          ],
        );
      },
    );

    test(
      'runs before and after collection hooks for every operation',
      () async {
        final storage = InMemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        final hook = RecordingActionHook();
        engine.addHook(hook);
        await engine.registerCollection(
          const CollectionSchema(
            name: 'posts',
            fields: [
              SchemaField(name: 'title', type: FieldType.text),
            ],
            accessRules: {
              CollectionOperation.list: AccessRule('true'),
              CollectionOperation.view: AccessRule('true'),
              CollectionOperation.create: AccessRule('true'),
              CollectionOperation.update: AccessRule('true'),
              CollectionOperation.delete: AccessRule('true'),
            },
          ),
        );

        final posts = engine.collection('posts');
        await posts.create(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post-1'),
            data: {'title': 'Hooked'},
          ),
        );
        await posts.get(const RecordIdentifier('post-1'));
        await posts.update(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post-1'),
            data: {'title': 'Updated'},
          ),
        );
        await posts.list();
        await posts.delete(const RecordIdentifier('post-1'));

        expect(
          hook.contexts.map(
            (context) => (
              context.operation,
              context.phase,
              context.record?.id.value,
            ),
          ),
          [
            (
              CollectionOperation.create,
              HookPhase.before,
              'post-1',
            ),
            (
              CollectionOperation.create,
              HookPhase.after,
              'post-1',
            ),
            (
              CollectionOperation.view,
              HookPhase.before,
              'post-1',
            ),
            (
              CollectionOperation.view,
              HookPhase.after,
              'post-1',
            ),
            (
              CollectionOperation.update,
              HookPhase.before,
              'post-1',
            ),
            (
              CollectionOperation.update,
              HookPhase.after,
              'post-1',
            ),
            (
              CollectionOperation.list,
              HookPhase.before,
              null,
            ),
            (
              CollectionOperation.list,
              HookPhase.after,
              null,
            ),
            (
              CollectionOperation.delete,
              HookPhase.before,
              'post-1',
            ),
            (
              CollectionOperation.delete,
              HookPhase.after,
              'post-1',
            ),
          ],
        );
      },
    );

    test(
      'lists records with field comparisons, sorting, and pagination',
      () async {
        final storage = InMemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        await engine.registerCollection(
          const CollectionSchema(
            name: 'posts',
            fields: [
              SchemaField(name: 'title', type: FieldType.text),
              SchemaField(name: 'published', type: FieldType.bool),
              SchemaField(name: 'views', type: FieldType.number),
            ],
            accessRules: {},
          ),
        );
        final posts = engine.collection('posts');

        await posts.create(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post-1'),
            data: {'title': 'Draft', 'published': false, 'views': 100},
          ),
        );
        await posts.create(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post-2'),
            data: {'title': 'Popular', 'published': true, 'views': 50},
          ),
        );
        await posts.create(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post-3'),
            data: {'title': 'Launch', 'published': true, 'views': 10},
          ),
        );

        final page = await posts.list(
          query: const QueryExpression(
            filters: [
              QueryFilter(
                field: 'published',
                operator: QueryOperator.equals,
                value: true,
              ),
              QueryFilter(
                field: 'views',
                operator: QueryOperator.greaterThanOrEquals,
                value: 10,
              ),
            ],
            sort: [
              QuerySort(field: 'views', direction: SortDirection.descending),
            ],
            pagination: QueryPagination(page: 2, perPage: 1),
          ),
        );

        expect(page.items.map((record) => record.id.value), ['post-3']);
        expect(page.page, 2);
        expect(page.perPage, 1);
        expect(page.totalItems, 2);
      },
    );

    test(
      'rejects unsupported query behavior outside the Engine contract',
      () async {
        final storage = InMemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        await engine.registerCollection(
          const CollectionSchema(
            name: 'posts',
            fields: [
              SchemaField(name: 'author', type: FieldType.relation),
            ],
            accessRules: {},
          ),
        );

        await expectLater(
          engine
              .collection('posts')
              .list(
                query: const QueryExpression(
                  filters: [
                    QueryFilter(
                      field: 'author.name',
                      operator: QueryOperator.equals,
                      value: 'Ada',
                    ),
                  ],
                ),
              ),
          throwsA(isA<QueryExpressionException>()),
        );
      },
    );

    test('runs hooks around authentication actions', () async {
      final storage = InMemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final hook = RecordingAuthenticationActionHook();
      engine.addAuthenticationHook(hook);

      final authRecord = await engine.runAuthenticationAction(
        collection: 'members',
        action: AuthenticationOperation.authenticate,
        run: () async => const AuthRecordIdentity(
          collection: 'members',
          id: RecordIdentifier('member-1'),
        ),
      );

      expect(authRecord.id.value, 'member-1');
      expect(
        hook.contexts.map(
          (context) => (
            context.collection,
            context.action,
            context.phase,
            context.authRecord?.id.value,
          ),
        ),
        [
          (
            'members',
            AuthenticationOperation.authenticate,
            HookPhase.before,
            null,
          ),
          (
            'members',
            AuthenticationOperation.authenticate,
            HookPhase.after,
            'member-1',
          ),
        ],
      );
    });

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

    test('does not update a record that does not exist', () async {
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
                id: RecordIdentifier('missing-post'),
                data: {'title': 'Missing post'},
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
    final matching =
        (_records[collection]?.values ?? const <Record>[])
            .where(
              (record) =>
                  query.filters.every((filter) => _matches(record, filter)),
            )
            .toList()
          ..sort((left, right) => _compareRecords(left, right, query.sort));

    final start = (query.pagination.page - 1) * query.pagination.perPage;
    final end = start + query.pagination.perPage;
    final items = start >= matching.length
        ? const <Record>[]
        : List<Record>.unmodifiable(
            matching.sublist(
              start,
              end > matching.length ? matching.length : end,
            ),
          );
    return RecordPage(
      items: items,
      page: query.pagination.page,
      perPage: query.pagination.perPage,
      totalItems: matching.length,
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

  bool _matches(Record record, QueryFilter filter) {
    final value = filter.field == 'id'
        ? record.id.value
        : record.data[filter.field];
    final comparison = _compareValues(value, filter.value);
    return switch (filter.operator) {
      QueryOperator.equals => value == filter.value,
      QueryOperator.notEquals => value != filter.value,
      QueryOperator.greaterThan => comparison > 0,
      QueryOperator.greaterThanOrEquals => comparison >= 0,
      QueryOperator.lessThan => comparison < 0,
      QueryOperator.lessThanOrEquals => comparison <= 0,
    };
  }

  int _compareRecords(
    Record left,
    Record right,
    List<QuerySort> sort,
  ) {
    for (final instruction in sort) {
      final leftValue = instruction.field == 'id'
          ? left.id.value
          : left.data[instruction.field];
      final rightValue = instruction.field == 'id'
          ? right.id.value
          : right.data[instruction.field];
      final comparison = _compareValues(leftValue, rightValue);
      if (comparison != 0) {
        return instruction.direction == SortDirection.ascending
            ? comparison
            : -comparison;
      }
    }
    return 0;
  }

  int _compareValues(Object? left, Object? right) {
    return switch ((left, right)) {
      (final num left, final num right) => left.compareTo(right),
      (final String left, final String right) => left.compareTo(right),
      (final bool left, final bool right) =>
        left == right
            ? 0
            : left
            ? 1
            : -1,
      (final DateTime left, final DateTime right) => left.compareTo(right),
      _ => left == right ? 0 : -1,
    };
  }
}

class RecordingActionHook extends ActionHook {
  final List<ActionHookContext> contexts = <ActionHookContext>[];

  @override
  Future<void> call(ActionHookContext context) async {
    contexts.add(context);
  }
}

class RecordingAuthenticationActionHook extends AuthenticationActionHook {
  final List<AuthenticationActionHookContext> contexts =
      <AuthenticationActionHookContext>[];

  @override
  Future<void> call(AuthenticationActionHookContext context) async {
    contexts.add(context);
  }
}
