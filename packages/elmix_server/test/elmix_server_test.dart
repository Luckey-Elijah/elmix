import 'dart:convert';

import 'package:elmix_engine/elmix_engine.dart';
import 'package:elmix_server/elmix_server.dart';
import 'package:test/test.dart';

void main() {
  group('ElmixServer Public API', () {
    test('lists collection records through Engine use cases', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: FieldType.text, required: true),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );
      await engine
          .collection('posts')
          .create(
            const Record(
              collection: 'posts',
              id: RecordIdentifier('post_1'),
              data: <String, Object?>{'title': 'Hello server'},
            ),
          );

      final response = await server.handle(
        const ElmixHttpRequest(
          method: 'GET',
          path: '/api/collections/posts/records',
        ),
      );

      expect(response.statusCode, 200);
      expect(response.body, <String, Object?>{
        'page': 1,
        'perPage': 30,
        'totalItems': 1,
        'items': <Object?>[
          <String, Object?>{
            'collection': 'posts',
            'id': 'post_1',
            'data': <String, Object?>{'title': 'Hello server'},
          },
        ],
      });
    });

    test('decodes structured list query payloads', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: FieldType.text, required: true),
            SchemaField(name: 'views', type: FieldType.number),
            SchemaField(name: 'published', type: FieldType.bool),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );

      final query = jsonEncode(<String, Object?>{
        'filters': <Object?>[
          <String, Object?>{
            'field': 'published',
            'operator': 'equals',
            'value': true,
          },
          <String, Object?>{
            'field': 'views',
            'operator': 'greaterThanOrEquals',
            'value': 10,
          },
        ],
        'sort': <Object?>[
          <String, Object?>{
            'field': 'title',
            'direction': 'descending',
          },
        ],
        'pagination': <String, Object?>{'page': 2, 'perPage': 10},
      });

      final response = await server.handle(
        ElmixHttpRequest(
          method: 'GET',
          path: '/api/collections/posts/records?query=$query',
        ),
      );

      expect(response.statusCode, 200);
      expect(storage.lastQuery, isNotNull);
      expect(storage.lastQuery!.filters, hasLength(2));
      expect(storage.lastQuery!.filters.first.field, 'published');
      expect(storage.lastQuery!.filters.first.operator, QueryOperator.equals);
      expect(storage.lastQuery!.filters.first.value, isTrue);
      expect(storage.lastQuery!.filters.last.field, 'views');
      expect(
        storage.lastQuery!.filters.last.operator,
        QueryOperator.greaterThanOrEquals,
      );
      expect(storage.lastQuery!.sort.single.field, 'title');
      expect(
        storage.lastQuery!.sort.single.direction,
        SortDirection.descending,
      );
      expect(storage.lastQuery!.pagination.page, 2);
      expect(storage.lastQuery!.pagination.perPage, 10);
    });

    test('authenticates Auth Records and accepts bearer tokens', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema.auth(
          name: 'members',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'email', type: FieldType.email, required: true),
            SchemaField(
              name: 'password',
              type: FieldType.password,
              required: true,
            ),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );
      await engine.registerCollection(
        const CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: FieldType.text, required: true),
          ],
          accessRules: <CollectionOperation, AccessRule>{
            CollectionOperation.list: AccessRule(
              'auth.collection == "members" && auth.id == "member_1"',
            ),
          },
        ),
      );
      await engine
          .collection('members')
          .create(
            const Record(
              collection: 'members',
              id: RecordIdentifier('member_1'),
              data: <String, Object?>{
                'email': 'ada@example.com',
                'password': 'correct horse',
              },
            ),
          );

      final auth = await server.handle(
        const ElmixHttpRequest(
          method: 'POST',
          path: '/api/collections/members/auth-with-password',
          body: <String, Object?>{
            'email': 'ada@example.com',
            'password': 'correct horse',
          },
        ),
      );

      expect(auth.statusCode, 200);
      final authBody = auth.body! as Map<String, Object?>;
      expect(authBody['token'], isA<String>());
      expect(
        (authBody['record']! as Map<String, Object?>)['id'],
        'member_1',
      );

      final allowed = await server.handle(
        ElmixHttpRequest(
          method: 'GET',
          path: '/api/collections/posts/records',
          headers: <String, String>{
            'authorization': 'Bearer ${authBody['token']}',
          },
        ),
      );

      expect(allowed.statusCode, 200);
    });

    test('creates, views, updates, and deletes collection records', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: FieldType.text, required: true),
            SchemaField(name: 'published', type: FieldType.bool),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );

      final create = await server.handle(
        const ElmixHttpRequest(
          method: 'POST',
          path: '/api/collections/posts/records',
          body: <String, Object?>{
            'id': 'post_1',
            'data': <String, Object?>{
              'title': 'Draft',
              'published': false,
            },
          },
        ),
      );
      expect(create.statusCode, 201);
      expect((create.body! as Map<String, Object?>)['id'], 'post_1');

      final view = await server.handle(
        const ElmixHttpRequest(
          method: 'GET',
          path: '/api/collections/posts/records/post_1',
        ),
      );
      expect(view.statusCode, 200);
      expect(view.body, <String, Object?>{
        'collection': 'posts',
        'id': 'post_1',
        'data': <String, Object?>{
          'title': 'Draft',
          'published': false,
        },
      });

      final update = await server.handle(
        const ElmixHttpRequest(
          method: 'PATCH',
          path: '/api/collections/posts/records/post_1',
          body: <String, Object?>{
            'data': <String, Object?>{
              'title': 'Published',
              'published': true,
            },
          },
        ),
      );
      expect(update.statusCode, 200);
      expect(
        (update.body! as Map<String, Object?>)['data'],
        <String, Object?>{
          'title': 'Published',
          'published': true,
        },
      );

      final delete = await server.handle(
        const ElmixHttpRequest(
          method: 'DELETE',
          path: '/api/collections/posts/records/post_1',
        ),
      );
      expect(delete.statusCode, 204);
      expect(delete.body, isNull);

      final missing = await server.handle(
        const ElmixHttpRequest(
          method: 'GET',
          path: '/api/collections/posts/records/post_1',
        ),
      );
      expect(missing.statusCode, 404);
    });

    test('merges PATCH data with the existing record', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: FieldType.text, required: true),
            SchemaField(name: 'body', type: FieldType.text, required: true),
            SchemaField(name: 'published', type: FieldType.bool),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );
      await engine
          .collection('posts')
          .create(
            const Record(
              collection: 'posts',
              id: RecordIdentifier('post_1'),
              data: <String, Object?>{
                'title': 'Draft',
                'body': 'Original body',
                'published': false,
              },
            ),
          );

      final response = await server.handle(
        const ElmixHttpRequest(
          method: 'PATCH',
          path: '/api/collections/posts/records/post_1',
          body: <String, Object?>{
            'data': <String, Object?>{'published': true},
          },
        ),
      );

      expect(response.statusCode, 200);
      expect(
        (response.body! as Map<String, Object?>)['data'],
        <String, Object?>{
          'title': 'Draft',
          'body': 'Original body',
          'published': true,
        },
      );
    });

    test('decodes JSON date strings before Engine validation', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema(
          name: 'events',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'startsAt', type: FieldType.date, required: true),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );

      final response = await server.handle(
        const ElmixHttpRequest(
          method: 'POST',
          path: '/api/collections/events/records',
          body: <String, Object?>{
            'id': 'event_1',
            'data': <String, Object?>{
              'startsAt': '2026-05-11T14:44:35.000Z',
            },
          },
        ),
      );

      expect(response.statusCode, 201);
      expect(
        (response.body! as Map<String, Object?>)['data'],
        <String, Object?>{
          'startsAt': '2026-05-11T14:44:35.000Z',
        },
      );
      expect(
        (await engine
                .collection('events')
                .get(const RecordIdentifier('event_1')))!
            .data['startsAt'],
        DateTime.utc(2026, 5, 11, 14, 44, 35),
      );
    });

    test(
      'passes request auth context into Engine and returns errors',
      () async {
        final storage = MemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        final server = ElmixServer(engine);

        await engine.registerCollection(
          const CollectionSchema(
            name: 'posts',
            fields: <SchemaField>[
              SchemaField.recordIdentifier(),
              SchemaField(name: 'title', type: FieldType.text, required: true),
            ],
            accessRules: <CollectionOperation, AccessRule>{
              CollectionOperation.list: AccessRule('auth.id == "member_1"'),
            },
          ),
        );

        final denied = await server.handle(
          const ElmixHttpRequest(
            method: 'GET',
            path: '/api/collections/posts/records',
          ),
        );
        expect(denied.statusCode, 403);
        expect(denied.body, <String, Object?>{
          'error': <String, Object?>{
            'code': 'forbidden',
            'message': 'Collection "posts" list request is not authorized.',
          },
        });

        final allowed = await server.handle(
          const ElmixHttpRequest(
            method: 'GET',
            path: '/api/collections/posts/records',
            headers: <String, String>{
              'x-elmix-auth-collection': 'members',
              'x-elmix-auth-id': 'member_1',
            },
          ),
        );
        expect(allowed.statusCode, 200);
      },
    );
  });

  group('ElmixServer Admin API', () {
    test('creates, lists, views, and updates collection schemas', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      final create = await server.handle(
        const ElmixHttpRequest(
          method: 'POST',
          path: '/api/admin/collections',
          body: <String, Object?>{
            'name': 'posts',
            'isAuthCollection': false,
            'fields': <Object?>[
              <String, Object?>{
                'name': 'id',
                'type': 'text',
                'required': true,
                'removable': false,
                'systemRole': 'recordIdentifier',
              },
              <String, Object?>{
                'name': 'title',
                'type': 'text',
                'required': true,
              },
            ],
            'accessRules': <String, Object?>{'list': 'true'},
          },
        ),
      );
      expect(create.statusCode, 201);
      expect((create.body! as Map<String, Object?>)['name'], 'posts');

      final list = await server.handle(
        const ElmixHttpRequest(
          method: 'GET',
          path: '/api/admin/collections',
        ),
      );
      expect(list.statusCode, 200);
      expect(
        (list.body! as Map<String, Object?>)['items'],
        hasLength(1),
      );

      final view = await server.handle(
        const ElmixHttpRequest(
          method: 'GET',
          path: '/api/admin/collections/posts',
        ),
      );
      expect(view.statusCode, 200);
      expect(
        (view.body! as Map<String, Object?>)['accessRules'],
        <String, Object?>{'list': 'true'},
      );

      final update = await server.handle(
        const ElmixHttpRequest(
          method: 'PUT',
          path: '/api/admin/collections/posts',
          body: <String, Object?>{
            'name': 'posts',
            'fields': <Object?>[
              <String, Object?>{
                'name': 'id',
                'type': 'text',
                'required': true,
                'removable': false,
                'systemRole': 'recordIdentifier',
              },
              <String, Object?>{'name': 'headline', 'type': 'text'},
            ],
            'accessRules': <String, Object?>{'list': ''},
          },
        ),
      );
      expect(update.statusCode, 200);
      expect(
        ((update.body! as Map<String, Object?>)['fields']! as List<Object?>)
            .map((field) => (field! as Map<String, Object?>)['name']),
        <String>['id', 'headline'],
      );
    });

    test('manages collection records for the Admin Control Plane', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: FieldType.text, required: true),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );

      final create = await server.handle(
        const ElmixHttpRequest(
          method: 'POST',
          path: '/api/admin/collections/posts/records',
          body: <String, Object?>{
            'id': 'post_1',
            'data': <String, Object?>{'title': 'Admin created'},
          },
        ),
      );
      expect(create.statusCode, 201);

      final list = await server.handle(
        const ElmixHttpRequest(
          method: 'GET',
          path: '/api/admin/collections/posts/records',
        ),
      );
      expect(list.statusCode, 200);
      expect((list.body! as Map<String, Object?>)['totalItems'], 1);

      final view = await server.handle(
        const ElmixHttpRequest(
          method: 'GET',
          path: '/api/admin/collections/posts/records/post_1',
        ),
      );
      expect(view.statusCode, 200);
      expect((view.body! as Map<String, Object?>)['id'], 'post_1');

      final update = await server.handle(
        const ElmixHttpRequest(
          method: 'PATCH',
          path: '/api/admin/collections/posts/records/post_1',
          body: <String, Object?>{
            'data': <String, Object?>{'title': 'Admin updated'},
          },
        ),
      );
      expect(update.statusCode, 200);
      expect(
        (update.body! as Map<String, Object?>)['data'],
        <String, Object?>{'title': 'Admin updated'},
      );

      final delete = await server.handle(
        const ElmixHttpRequest(
          method: 'DELETE',
          path: '/api/admin/collections/posts/records/post_1',
        ),
      );
      expect(delete.statusCode, 204);
    });
  });
}

class MemoryStorageAdapter implements StorageAdapter {
  final Map<String, CollectionSchema> _schemas = <String, CollectionSchema>{};
  final Map<String, Map<String, Record>> _records =
      <String, Map<String, Record>>{};
  QueryExpression? lastQuery;

  @override
  Future<void> deleteRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    _records[collection]?.remove(id.value);
  }

  @override
  Future<CollectionSchema?> getCollectionSchema(String name) async {
    return _schemas[name];
  }

  @override
  Future<Record?> getRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    return _records[collection]?[id.value];
  }

  @override
  Future<List<CollectionSchema>> listCollectionSchemas() async {
    return List<CollectionSchema>.unmodifiable(_schemas.values);
  }

  @override
  Future<RecordPage> listRecords({
    required String collection,
    QueryExpression query = const QueryExpression(),
  }) async {
    lastQuery = query;
    final matching = (_records[collection]?.values ?? const <Record>[])
        .toList();
    return RecordPage(
      items: List<Record>.unmodifiable(matching),
      page: query.pagination.page,
      perPage: query.pagination.perPage,
      totalItems: matching.length,
    );
  }

  @override
  Future<void> putCollectionSchema(CollectionSchema schema) async {
    _schemas[schema.name] = schema;
  }

  @override
  Future<Record> putRecord(Record record) async {
    _records.putIfAbsent(
      record.collection,
      () => <String, Record>{},
    )[record.id.value] = record;
    return record;
  }
}
