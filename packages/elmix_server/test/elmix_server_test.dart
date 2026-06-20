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
            SchemaField(name: 'title', type: .text, required: true),
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
          method: .get,
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
            SchemaField(name: 'title', type: .text, required: true),
            SchemaField(name: 'views', type: .number),
            SchemaField(name: 'published', type: .bool),
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
          method: ElmixHttpRequestMethod.get,
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

    test('does not expose built-in Admin Account records publicly', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema.auth(
          name: '_admins',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'email', type: .email, required: true),
            SchemaField(
              name: 'passwordHash',
              type: .password,
              required: true,
            ),
          ],
          accessRules: <CollectionOperation, AccessRule>{
            .list: AccessRule('false'),
            .view: AccessRule('false'),
            .create: AccessRule('false'),
            .update: AccessRule('false'),
            .delete: AccessRule('false'),
          },
        ),
      );
      await engine
          .collection('_admins', context: RequestContext.system)
          .create(
            const AuthRecord(
              collection: '_admins',
              id: RecordIdentifier('admin@example.com'),
              data: <String, Object?>{
                'email': 'admin@example.com',
                'passwordHash': 'stored-password-hash',
              },
            ),
          );

      final response = await server.handle(
        const ElmixHttpRequest(
          method: .get,
          path: '/api/collections/_admins/records',
        ),
      );

      expect(response.statusCode, 403);
      expect(response.body.toString(), isNot(contains('stored-password-hash')));
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
            SchemaField(name: 'email', type: .email, required: true),
            SchemaField(
              name: 'password',
              type: .password,
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
            SchemaField(name: 'title', type: .text, required: true),
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
          method: .post,
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
          method: .get,
          path: '/api/collections/posts/records',
          headers: <String, String>{
            'authorization': 'Bearer ${authBody['token']}',
          },
        ),
      );

      expect(allowed.statusCode, 200);
    });

    test(
      'authenticates Auth Records without requiring public list access',
      () async {
        final storage = MemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        final server = ElmixServer(engine);

        await engine.registerCollection(
          const CollectionSchema.auth(
            name: 'members',
            fields: <SchemaField>[
              SchemaField.recordIdentifier(),
              SchemaField(name: 'email', type: .email, required: true),
              SchemaField(
                name: 'password',
                type: .password,
                required: true,
              ),
            ],
            accessRules: <CollectionOperation, AccessRule>{
              CollectionOperation.list: AccessRule('auth.id == "member_1"'),
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

        final deniedList = await server.handle(
          const ElmixHttpRequest(
            method: .get,
            path: '/api/collections/members/records',
          ),
        );
        expect(deniedList.statusCode, 403);

        final auth = await server.handle(
          const ElmixHttpRequest(
            method: .post,
            path: '/api/collections/members/auth-with-password',
            body: <String, Object?>{
              'email': 'ada@example.com',
              'password': 'correct horse',
            },
          ),
        );

        expect(auth.statusCode, 200);
        expect(
          (auth.body! as Map<String, Object?>)['token'],
          isA<String>(),
        );
      },
    );

    test('issues unique bearer tokens for repeated authentication', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema.auth(
          name: 'members',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'email', type: .email, required: true),
            SchemaField(
              name: 'password',
              type: .password,
              required: true,
            ),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
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

      Future<String> authenticate() async {
        final response = await server.handle(
          const ElmixHttpRequest(
            method: .post,
            path: '/api/collections/members/auth-with-password',
            body: <String, Object?>{
              'email': 'ada@example.com',
              'password': 'correct horse',
            },
          ),
        );
        expect(response.statusCode, 200);
        return (response.body! as Map<String, Object?>)['token']! as String;
      }

      final firstToken = await authenticate();
      final secondToken = await authenticate();

      expect(firstToken, isNot(secondToken));
      expect(
        firstToken,
        isNot(base64Url.encode(utf8.encode('members:member_1:0'))),
      );
    });

    test('decodes date query filter values before listing records', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema(
          name: 'events',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'startsAt', type: .date, required: true),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );
      await engine
          .collection('events')
          .create(
            Record(
              collection: 'events',
              id: const RecordIdentifier('event_1'),
              data: <String, Object?>{
                'startsAt': DateTime.utc(2026, 5, 13),
              },
            ),
          );
      final query = jsonEncode(<String, Object?>{
        'filters': <Object?>[
          <String, Object?>{
            'field': 'startsAt',
            'operator': 'greaterThanOrEquals',
            'value': '2026-05-13T00:00:00.000Z',
          },
        ],
      });

      final response = await server.handle(
        ElmixHttpRequest(
          method: .get,
          path: '/api/collections/events/records?query=$query',
        ),
      );

      expect(response.statusCode, 200);
      final body = response.body! as Map<String, Object?>;
      expect(body['totalItems'], 1);
      expect(storage.lastQuery!.filters.single.value, isA<DateTime>());
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
            SchemaField(name: 'title', type: .text, required: true),
            SchemaField(name: 'published', type: .bool),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );

      final create = await server.handle(
        const ElmixHttpRequest(
          method: .post,
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
          method: .get,
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
          method: .patch,
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
          method: .delete,
          path: '/api/collections/posts/records/post_1',
        ),
      );
      expect(delete.statusCode, 204);
      expect(delete.body, isNull);

      final missing = await server.handle(
        const ElmixHttpRequest(
          method: .get,
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
            SchemaField(name: 'title', type: .text, required: true),
            SchemaField(name: 'body', type: .text, required: true),
            SchemaField(name: 'published', type: .bool),
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
          method: .patch,
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
            SchemaField(name: 'startsAt', type: .date, required: true),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );

      final response = await server.handle(
        const ElmixHttpRequest(
          method: .post,
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
              SchemaField(name: 'title', type: .text, required: true),
            ],
            accessRules: <CollectionOperation, AccessRule>{
              .list: AccessRule('auth.id == "member_1"'),
            },
          ),
        );

        final denied = await server.handle(
          const ElmixHttpRequest(
            method: .get,
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
            method: .get,
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
          method: .post,
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
          method: .get,
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
          method: .get,
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
          method: .put,
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

    test(
      'rejects deletion of framework-owned internal collections',
      () async {
        final storage = MemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        final server = ElmixServer(
          engine,
          adminAccounts: const <ServerAdminAccount>[
            ServerAdminAccount(
              id: AdminAccountIdentifier('admin_1'),
              email: 'admin@example.test',
              password: 'admin-secret',
            ),
          ],
        );
        await engine.registerCollection(
          const CollectionSchema(
            name: '_admins',
            fields: <SchemaField>[
              SchemaField.recordIdentifier(),
              SchemaField(name: 'email', type: .email, required: true),
              SchemaField(
                name: 'passwordHash',
                type: .password,
                required: true,
              ),
            ],
            accessRules: <CollectionOperation, AccessRule>{},
          ),
        );
        final auth = await server.handle(
          const ElmixHttpRequest(
            method: .post,
            path: '/api/admin/auth-with-password',
            body: <String, Object?>{
              'email': 'admin@example.test',
              'password': 'admin-secret',
            },
          ),
        );
        final token = (auth.body! as Map<String, Object?>)['token']! as String;

        final deletion = await server.handle(
          ElmixHttpRequest(
            method: .delete,
            path: '/api/admin/collections/_admins',
            headers: <String, String>{'authorization': 'Bearer $token'},
          ),
        );

        expect(deletion.statusCode, 403);
        expect(await engine.getCollectionSchema('_admins'), isNotNull);
      },
    );

    test('manages collection records for the Admin Control Plane', () async {
      final storage = MemoryStorageAdapter();
      final engine = ElmixEngine(storage: storage);
      final server = ElmixServer(engine);

      await engine.registerCollection(
        const CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: .text, required: true),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        ),
      );

      final create = await server.handle(
        const ElmixHttpRequest(
          method: .post,
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
          method: .get,
          path: '/api/admin/collections/posts/records',
        ),
      );
      expect(list.statusCode, 200);
      expect((list.body! as Map<String, Object?>)['totalItems'], 1);

      final view = await server.handle(
        const ElmixHttpRequest(
          method: .get,
          path: '/api/admin/collections/posts/records/post_1',
        ),
      );
      expect(view.statusCode, 200);
      expect((view.body! as Map<String, Object?>)['id'], 'post_1');

      final update = await server.handle(
        const ElmixHttpRequest(
          method: .patch,
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
          method: .delete,
          path: '/api/admin/collections/posts/records/post_1',
        ),
      );
      expect(delete.statusCode, 204);
    });

    test(
      'uses system context for authenticated Admin API record routes',
      () async {
        final storage = MemoryStorageAdapter();
        final engine = ElmixEngine(storage: storage);
        final server = ElmixServer(
          engine,
          adminAccounts: const <ServerAdminAccount>[
            ServerAdminAccount(
              id: AdminAccountIdentifier('admin_1'),
              email: 'admin@example.test',
              password: 'admin-secret',
            ),
          ],
        );

        await engine.registerCollection(
          const CollectionSchema(
            name: 'posts',
            fields: <SchemaField>[
              SchemaField.recordIdentifier(),
              SchemaField(name: 'title', type: .text, required: true),
            ],
            accessRules: <CollectionOperation, AccessRule>{
              .list: AccessRule('false'),
              .view: AccessRule('false'),
              .create: AccessRule('false'),
              .update: AccessRule('false'),
              .delete: AccessRule('false'),
            },
          ),
        );

        final auth = await server.handle(
          const ElmixHttpRequest(
            method: .post,
            path: '/api/admin/auth-with-password',
            body: <String, Object?>{
              'email': 'admin@example.test',
              'password': 'admin-secret',
            },
          ),
        );
        final token = (auth.body! as Map<String, Object?>)['token']! as String;
        final headers = <String, String>{'authorization': 'Bearer $token'};

        final create = await server.handle(
          ElmixHttpRequest(
            method: .post,
            path: '/api/admin/collections/posts/records',
            headers: headers,
            body: const <String, Object?>{
              'id': 'post_1',
              'data': <String, Object?>{'title': 'Admin created'},
            },
          ),
        );
        final list = await server.handle(
          ElmixHttpRequest(
            method: .get,
            path: '/api/admin/collections/posts/records',
            headers: headers,
          ),
        );
        final view = await server.handle(
          ElmixHttpRequest(
            method: .get,
            path: '/api/admin/collections/posts/records/post_1',
            headers: headers,
          ),
        );
        final update = await server.handle(
          ElmixHttpRequest(
            method: .patch,
            path: '/api/admin/collections/posts/records/post_1',
            headers: headers,
            body: const <String, Object?>{
              'data': <String, Object?>{'title': 'Admin updated'},
            },
          ),
        );
        final delete = await server.handle(
          ElmixHttpRequest(
            method: .delete,
            path: '/api/admin/collections/posts/records/post_1',
            headers: headers,
          ),
        );

        expect(create.statusCode, 201);
        expect(list.statusCode, 200);
        expect(view.statusCode, 200);
        expect(update.statusCode, 200);
        expect(delete.statusCode, 204);
      },
    );
  });

  group('ElmixServer authentication', () {
    test('authenticates Admin Accounts separately from Auth Records', () async {
      final engine = ElmixEngine(storage: MemoryStorageAdapter());
      final server = ElmixServer(
        engine,
        adminAccounts: const <ServerAdminAccount>[
          ServerAdminAccount(
            id: AdminAccountIdentifier('admin_1'),
            email: 'admin@example.test',
            password: 'admin-secret',
          ),
        ],
      );

      final response = await server.handle(
        const ElmixHttpRequest(
          method: .post,
          path: '/api/admin/auth-with-password',
          body: <String, Object?>{
            'email': 'admin@example.test',
            'password': 'admin-secret',
          },
        ),
      );

      expect(response.statusCode, 200);
      expect((response.body! as Map<String, Object?>)['admin'], {
        'id': 'admin_1',
        'email': 'admin@example.test',
      });
      expect(
        (response.body! as Map<String, Object?>)['token'],
        allOf(isA<String>(), isNot(contains('admin_1'))),
      );
      expect(response.body! as Map<String, Object?>, isNot(contains('record')));
    });

    test('rejects forged Admin Account bearer tokens after login', () async {
      final engine = ElmixEngine(storage: MemoryStorageAdapter());
      final server = ElmixServer(
        engine,
        adminAccounts: const <ServerAdminAccount>[
          ServerAdminAccount(
            id: AdminAccountIdentifier('admin_1'),
            email: 'admin@example.test',
            password: 'admin-secret',
          ),
        ],
      );

      final auth = await server.handle(
        const ElmixHttpRequest(
          method: .post,
          path: '/api/admin/auth-with-password',
          body: <String, Object?>{
            'email': 'admin@example.test',
            'password': 'admin-secret',
          },
        ),
      );
      final forged = await server.handle(
        const ElmixHttpRequest(
          method: .get,
          path: '/api/admin/collections',
          headers: <String, String>{
            'authorization': 'Bearer admin:admin_1',
          },
        ),
      );

      expect(auth.statusCode, 200);
      expect(forged.statusCode, 401);
      expect(
        ((forged.body! as Map<String, Object?>)['error']!
            as Map<String, Object?>)['code'],
        'admin_session_required',
      );
    });

    test(
      'authenticates Auth Records and uses bearer tokens for Access Rules',
      () async {
        final engine = ElmixEngine(storage: MemoryStorageAdapter());
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
                  'email': 'member@example.test',
                  'password': 'secret',
                },
              ),
            );
        await engine
            .collection('posts')
            .create(
              const Record(
                collection: 'posts',
                id: RecordIdentifier('post_1'),
                data: <String, Object?>{'title': 'Member post'},
              ),
            );
        final server = ElmixServer(engine);

        final auth = await server.handle(
          const ElmixHttpRequest(
            method: .post,
            path: '/api/collections/members/auth-with-password',
            body: <String, Object?>{
              'email': 'member@example.test',
              'password': 'secret',
            },
          ),
        );
        final token = (auth.body! as Map<String, Object?>)['token']! as String;
        final allowed = await server.handle(
          ElmixHttpRequest(
            method: .get,
            path: '/api/collections/posts/records',
            headers: <String, String>{'authorization': 'Bearer $token'},
          ),
        );

        expect(auth.statusCode, 200);
        expect(token, isA<String>());
        expect(token, isNot('record-session:members:member_1'));
        expect(
          ((auth.body! as Map<String, Object?>)['record']!
              as Map<String, Object?>)['data'],
          <String, Object?>{'email': 'member@example.test'},
        );
        expect(allowed.statusCode, 200);
        expect((allowed.body! as Map<String, Object?>)['totalItems'], 1);
      },
    );

    test('does not trust forged Auth Record bearer tokens', () async {
      final engine = ElmixEngine(storage: MemoryStorageAdapter());
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
      await engine
          .collection('posts')
          .create(
            const Record(
              collection: 'posts',
              id: RecordIdentifier('post_1'),
              data: <String, Object?>{'title': 'Protected'},
            ),
          );
      final server = ElmixServer(engine);

      final response = await server.handle(
        const ElmixHttpRequest(
          method: .get,
          path: '/api/collections/posts/records',
          headers: <String, String>{
            'authorization': 'Bearer record:members:member_1',
          },
        ),
      );

      expect(response.statusCode, 403);
    });

    test(
      'authenticates Auth Records without using the public list rule',
      () async {
        final engine = ElmixEngine(storage: MemoryStorageAdapter());
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
            accessRules: <CollectionOperation, AccessRule>{
              CollectionOperation.list: AccessRule('false'),
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
                  'email': 'member@example.test',
                  'password': 'secret',
                },
              ),
            );
        final server = ElmixServer(engine);

        final response = await server.handle(
          const ElmixHttpRequest(
            method: .post,
            path: '/api/collections/members/auth-with-password',
            body: <String, Object?>{
              'email': 'member@example.test',
              'password': 'secret',
            },
          ),
        );

        expect(response.statusCode, 200);
        expect(
          (response.body! as Map<String, Object?>)['token'],
          isA<String>(),
        );
      },
    );

    test(
      'requires Admin Account sessions when admin credentials are configured',
      () async {
        final engine = ElmixEngine(storage: MemoryStorageAdapter());
        final server = ElmixServer(
          engine,
          adminAccounts: const <ServerAdminAccount>[
            ServerAdminAccount(
              id: AdminAccountIdentifier('admin_1'),
              email: 'admin@example.test',
              password: 'admin-secret',
            ),
          ],
        );

        final rejected = await server.handle(
          const ElmixHttpRequest(
            method: .get,
            path: '/api/admin/collections',
          ),
        );
        final auth = await server.handle(
          const ElmixHttpRequest(
            method: .post,
            path: '/api/admin/auth-with-password',
            body: <String, Object?>{
              'email': 'admin@example.test',
              'password': 'admin-secret',
            },
          ),
        );
        final token = (auth.body! as Map<String, Object?>)['token']! as String;
        final accepted = await server.handle(
          ElmixHttpRequest(
            method: .get,
            path: '/api/admin/collections',
            headers: <String, String>{'authorization': 'Bearer $token'},
          ),
        );

        expect(rejected.statusCode, 401);
        expect(
          ((rejected.body! as Map<String, Object?>)['error']!
              as Map<String, Object?>)['code'],
          'admin_session_required',
        );
        expect(accepted.statusCode, 200);
      },
    );
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
        .where(
          (record) => query.filters.every((filter) => _matches(record, filter)),
        )
        .toList();
    final start = (query.pagination.page - 1) * query.pagination.perPage;
    final end = start + query.pagination.perPage;
    final items = start >= matching.length
        ? const <Record>[]
        : matching.sublist(
            start,
            end > matching.length ? matching.length : end,
          );
    return RecordPage(
      items: List<Record>.unmodifiable(items),
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
  Future<void> deleteCollectionSchema(String name) async {
    _schemas.remove(name);
    _records.remove(name);
  }

  @override
  Future<Record> putRecord(Record record) async {
    _records.putIfAbsent(
      record.collection,
      () => <String, Record>{},
    )[record.id.value] = record;
    return record;
  }

  bool _matches(Record record, QueryFilter filter) {
    final value = filter.field == 'id'
        ? record.id.value
        : record.data[filter.field];
    return switch (filter.operator) {
      QueryOperator.equals => value == filter.value,
      QueryOperator.notEquals => value != filter.value,
      QueryOperator.greaterThan => _compare(value, filter.value) > 0,
      QueryOperator.greaterThanOrEquals => _compare(value, filter.value) >= 0,
      QueryOperator.lessThan => _compare(value, filter.value) < 0,
      QueryOperator.lessThanOrEquals => _compare(value, filter.value) <= 0,
    };
  }

  int _compare(Object? left, Object? right) {
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
