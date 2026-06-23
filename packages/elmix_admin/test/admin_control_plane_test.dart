import 'package:elmix_admin/elmix_admin.dart';
import 'package:elmix_engine/elmix_engine.dart';
import 'package:elmix_server/elmix_server.dart';
import 'package:test/test.dart';

void main() {
  group('AdminBootstrap', () {
    test('creates Admin Accounts in an internal non-auth collection', () async {
      final engine = ElmixEngine(storage: MemoryStorageAdapter());
      final bootstrap = AdminBootstrap(engine);

      await bootstrap.createAdminAccount(
        email: 'admin@example.test',
        password: 'admin-secret',
      );

      final schema = await engine.getCollectionSchema('_admins');
      expect(schema, isNotNull);
      expect(schema!.isAuthCollection, false);
      final admin = await engine
          .collection('_admins', context: RequestContext.system)
          .get(const RecordIdentifier('admin@example.test'));
      expect(admin?.data['email'], 'admin@example.test');
      expect(admin?.data['passwordHash'], isNot('admin-secret'));
      expect(admin?.data['passwordHash'], startsWith(r'pbkdf2-sha256$'));
    });
  });

  group('AdminControlPlane', () {
    test('logs in and sends subsequent work through the Admin API', () async {
      final engine = ElmixEngine(storage: MemoryStorageAdapter());
      final bootstrap = AdminBootstrap(engine);
      await bootstrap.createAdminAccount(
        email: 'admin@example.test',
        password: 'admin-secret',
      );
      final server = ElmixServer(
        engine,
      );
      final transport = ServerAdminApiTransport(server);
      final controlPlane = AdminControlPlane(
        AdminApiClient(
          baseUrl: Uri.parse('http://localhost'),
          transport: transport,
        ),
      );

      final session = await controlPlane.login(
        email: 'admin@example.test',
        password: 'admin-secret',
      );
      final created = await controlPlane.createCollectionSchema(
        const CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'title', type: .text, required: true),
          ],
          accessRules: <CollectionOperation, AccessRule>{
            .list: AccessRule('true'),
          },
        ),
      );
      final schemas = await controlPlane.listCollectionSchemas();

      expect(session.admin.email, 'admin@example.test');
      expect(session.admin.id, 'admin@example.test');
      expect(created.name, 'posts');
      expect(schemas.map((schema) => schema.name), contains('posts'));
      expect(
        transport.requests.map((request) => request.url.path),
        <String>[
          '/api/admin/auth-with-password',
          '/api/admin/collections',
          '/api/admin/collections',
        ],
      );
      expect(
        transport.requests.last.headers['authorization'],
        'Bearer ${session.token}',
      );
    });

    test(
      'lists Admin Accounts through the Admin API without credentials',
      () async {
        final engine = ElmixEngine(storage: MemoryStorageAdapter());
        final bootstrap = AdminBootstrap(engine);
        await bootstrap.createAdminAccount(
          email: 'admin@example.test',
          password: 'admin-secret',
        );
        final server = ElmixServer(engine);
        final transport = ServerAdminApiTransport(server);
        final controlPlane = AdminControlPlane(
          AdminApiClient(
            baseUrl: Uri.parse('http://localhost'),
            transport: transport,
          ),
        );

        await controlPlane.login(
          email: 'admin@example.test',
          password: 'admin-secret',
        );
        final accounts = await controlPlane.listAdminAccounts();

        expect(accounts, hasLength(1));
        expect(accounts.single.id, 'admin@example.test');
        expect(accounts.single.email, 'admin@example.test');
        expect(
          transport.requests.last.url.path,
          '/api/admin/accounts',
        );
      },
    );

    test('blocks generic record access to internal Admin Accounts', () async {
      final engine = ElmixEngine(storage: MemoryStorageAdapter());
      final bootstrap = AdminBootstrap(engine);
      await bootstrap.createAdminAccount(
        email: 'admin@example.test',
        password: 'admin-secret',
      );
      final server = ElmixServer(engine);
      final controlPlane = AdminControlPlane(
        AdminApiClient(
          baseUrl: Uri.parse('http://localhost'),
          transport: ServerAdminApiTransport(server),
        ),
      );
      final session = await controlPlane.login(
        email: 'admin@example.test',
        password: 'admin-secret',
      );

      final response = await server.handle(
        ElmixHttpRequest(
          method: .get,
          path: '/api/admin/collections/_admins/records',
          headers: <String, String>{
            'authorization': 'Bearer ${session.token}',
          },
        ),
      );

      expect(response.statusCode, 403);
      expect(response.body, <String, Object?>{
        'error': <String, Object?>{
          'code': 'forbidden',
          'message': 'Admin Accounts must use dedicated Admin API routes.',
        },
      });
    });

    test(
      'creates an Admin Account without returning its password hash',
      () async {
        final engine = ElmixEngine(storage: MemoryStorageAdapter());
        final bootstrap = AdminBootstrap(engine);
        await bootstrap.createAdminAccount(
          email: 'admin@example.test',
          password: 'admin-secret',
        );
        final server = ElmixServer(engine);
        final controlPlane = AdminControlPlane(
          AdminApiClient(
            baseUrl: Uri.parse('http://localhost'),
            transport: ServerAdminApiTransport(server),
          ),
        );
        await controlPlane.login(
          email: 'admin@example.test',
          password: 'admin-secret',
        );

        final created = await controlPlane.createAdminAccount(
          email: 'second@example.test',
          password: 'second-secret',
        );
        final stored = await engine
            .collection('_admins', context: RequestContext.system)
            .get(const RecordIdentifier('second@example.test'));

        expect(created.id, 'second@example.test');
        expect(created.email, 'second@example.test');
        expect(stored?.data['passwordHash'], startsWith(r'pbkdf2-sha256$'));
        expect(stored?.data['passwordHash'], isNot('second-secret'));
      },
    );

    test(
      'changes an Admin Account password through the Admin API',
      () async {
        final engine = ElmixEngine(storage: MemoryStorageAdapter());
        final bootstrap = AdminBootstrap(engine);
        await bootstrap.createAdminAccount(
          email: 'admin@example.test',
          password: 'admin-secret',
        );
        final server = ElmixServer(engine);
        final transport = ServerAdminApiTransport(server);
        final controlPlane = AdminControlPlane(
          AdminApiClient(
            baseUrl: Uri.parse('http://localhost'),
            transport: transport,
          ),
        );
        await controlPlane.login(
          email: 'admin@example.test',
          password: 'admin-secret',
        );
        await controlPlane.createAdminAccount(
          email: 'second@example.test',
          password: 'second-secret',
        );

        final changed = await controlPlane.changeAdminAccountPassword(
          id: 'second@example.test',
          password: 'rotated-secret',
        );
        final secondControlPlane = AdminControlPlane(
          AdminApiClient(
            baseUrl: Uri.parse('http://localhost'),
            transport: transport,
          ),
        );

        expect(changed.email, 'second@example.test');
        await expectLater(
          secondControlPlane.login(
            email: 'second@example.test',
            password: 'second-secret',
          ),
          throwsA(
            isA<AdminApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
        final session = await secondControlPlane.login(
          email: 'second@example.test',
          password: 'rotated-secret',
        );
        expect(session.admin.email, 'second@example.test');
      },
    );

    test('refuses to delete the last remaining Admin Account', () async {
      final engine = ElmixEngine(storage: MemoryStorageAdapter());
      final bootstrap = AdminBootstrap(engine);
      await bootstrap.createAdminAccount(
        email: 'admin@example.test',
        password: 'admin-secret',
      );
      final server = ElmixServer(engine);
      final controlPlane = AdminControlPlane(
        AdminApiClient(
          baseUrl: Uri.parse('http://localhost'),
          transport: ServerAdminApiTransport(server),
        ),
      );
      await controlPlane.login(
        email: 'admin@example.test',
        password: 'admin-secret',
      );

      await expectLater(
        controlPlane.deleteAdminAccount('admin@example.test'),
        throwsA(
          isA<AdminApiException>()
              .having((error) => error.statusCode, 'statusCode', 409)
              .having((error) => error.code, 'code', 'last_admin_account'),
        ),
      );
    });

    test('deletes an Admin Account when another account remains', () async {
      final engine = ElmixEngine(storage: MemoryStorageAdapter());
      final bootstrap = AdminBootstrap(engine);
      await bootstrap.createAdminAccount(
        email: 'admin@example.test',
        password: 'admin-secret',
      );
      final server = ElmixServer(engine);
      final controlPlane = AdminControlPlane(
        AdminApiClient(
          baseUrl: Uri.parse('http://localhost'),
          transport: ServerAdminApiTransport(server),
        ),
      );
      await controlPlane.login(
        email: 'admin@example.test',
        password: 'admin-secret',
      );
      await controlPlane.createAdminAccount(
        email: 'second@example.test',
        password: 'second-secret',
      );

      await controlPlane.deleteAdminAccount('second@example.test');
      final accounts = await controlPlane.listAdminAccounts();

      expect(accounts.map((account) => account.email), <String>[
        'admin@example.test',
      ]);
    });

    test(
      'returns duplicate and missing Admin Account error envelopes',
      () async {
        final engine = ElmixEngine(storage: MemoryStorageAdapter());
        final bootstrap = AdminBootstrap(engine);
        await bootstrap.createAdminAccount(
          email: 'admin@example.test',
          password: 'admin-secret',
        );
        final server = ElmixServer(engine);
        final controlPlane = AdminControlPlane(
          AdminApiClient(
            baseUrl: Uri.parse('http://localhost'),
            transport: ServerAdminApiTransport(server),
          ),
        );
        await controlPlane.login(
          email: 'admin@example.test',
          password: 'admin-secret',
        );

        await expectLater(
          controlPlane.createAdminAccount(
            email: 'admin@example.test',
            password: 'another-secret',
          ),
          throwsA(
            isA<AdminApiException>()
                .having((error) => error.statusCode, 'statusCode', 409)
                .having(
                  (error) => error.code,
                  'code',
                  'duplicate_admin_account',
                ),
          ),
        );
        await expectLater(
          controlPlane.changeAdminAccountPassword(
            id: 'missing@example.test',
            password: 'new-secret',
          ),
          throwsA(
            isA<AdminApiException>()
                .having((error) => error.statusCode, 'statusCode', 404)
                .having(
                  (error) => error.code,
                  'code',
                  'admin_account_not_found',
                ),
          ),
        );
      },
    );

    test(
      'manages fields, Access Rules, and records over the Admin API',
      () async {
        final engine = ElmixEngine(storage: MemoryStorageAdapter());
        final server = ElmixServer(engine);
        final transport = ServerAdminApiTransport(server);
        final controlPlane = AdminControlPlane(
          AdminApiClient(
            baseUrl: Uri.parse('http://localhost'),
            transport: transport,
          ),
        );

        await controlPlane.createCollectionSchema(
          const CollectionSchema(
            name: 'posts',
            fields: <SchemaField>[SchemaField.recordIdentifier()],
            accessRules: <CollectionOperation, AccessRule>{},
          ),
        );
        final withField = await controlPlane.createSchemaField(
          collection: 'posts',
          field: const SchemaField(
            name: 'title',
            type: .text,
            required: true,
          ),
        );
        final withRules = await controlPlane.updateAccessRules(
          collection: 'posts',
          accessRules: const <CollectionOperation, AccessRule>{
            .list: AccessRule('true'),
            .view: AccessRule('true'),
          },
        );
        final created = await controlPlane.createRecord(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post_1'),
            data: <String, Object?>{'title': 'Admin created'},
          ),
        );
        final page = await controlPlane.listRecords('posts');
        final updated = await controlPlane.updateRecord(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post_1'),
            data: <String, Object?>{'title': 'Admin updated'},
          ),
        );
        await controlPlane.deleteRecord(
          collection: 'posts',
          id: const RecordIdentifier('post_1'),
        );

        expect(withField.fields.map((field) => field.name), ['id', 'title']);
        expect(
          withRules.accessRules[CollectionOperation.list]?.expression,
          'true',
        );
        expect(created.data['title'], 'Admin created');
        expect(page.totalItems, 1);
        expect(updated.data['title'], 'Admin updated');
        await expectLater(
          controlPlane.viewRecord(
            collection: 'posts',
            id: const RecordIdentifier('post_1'),
          ),
          throwsA(
            isA<AdminApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              404,
            ),
          ),
        );
        expect(
          transport.requests.map((request) => request.url.path),
          containsAll(<String>[
            '/api/admin/collections/posts',
            '/api/admin/collections/posts/records',
            '/api/admin/collections/posts/records/post_1',
          ]),
        );
      },
    );

    test(
      'updates fields and deletes Collection Schemas over the Admin API',
      () async {
        final engine = ElmixEngine(storage: MemoryStorageAdapter());
        final server = ElmixServer(engine);
        final transport = ServerAdminApiTransport(server);
        final controlPlane = AdminControlPlane(
          AdminApiClient(
            baseUrl: Uri.parse('http://localhost'),
            transport: transport,
          ),
        );

        await controlPlane.createCollectionSchema(
          const CollectionSchema(
            name: 'posts',
            fields: <SchemaField>[
              SchemaField.recordIdentifier(),
              SchemaField(name: 'title', type: .text),
            ],
            accessRules: <CollectionOperation, AccessRule>{},
          ),
        );
        final edited = await controlPlane.updateSchemaField(
          collection: 'posts',
          field: const SchemaField(
            name: 'title',
            type: .text,
            required: true,
          ),
        );

        await controlPlane.deleteCollectionSchema('posts');

        expect(
          edited.fields.firstWhere((field) => field.name == 'title').required,
          isTrue,
        );
        expect(await controlPlane.listCollectionSchemas(), isEmpty);
        expect(
          transport.requests.map(
            (request) =>
                '${request.method} '
                '${request.url.path}',
          ),
          containsAll(<String>[
            'PUT /api/admin/collections/posts',
            'DELETE /api/admin/collections/posts',
          ]),
        );
      },
    );

    test(
      'deletes Collection Schemas with path delimiters in their names',
      () async {
        final engine = ElmixEngine(storage: MemoryStorageAdapter());
        final server = ElmixServer(engine);
        final transport = ServerAdminApiTransport(server);
        final controlPlane = AdminControlPlane(
          AdminApiClient(
            baseUrl: Uri.parse('http://localhost'),
            transport: transport,
          ),
        );

        await controlPlane.createCollectionSchema(
          const CollectionSchema(
            name: 'drafts/2026',
            fields: <SchemaField>[SchemaField.recordIdentifier()],
            accessRules: <CollectionOperation, AccessRule>{},
          ),
        );

        await controlPlane.deleteCollectionSchema('drafts/2026');

        expect(await controlPlane.listCollectionSchemas(), isEmpty);
        expect(
          transport.requests.map((request) => request.url.path),
          contains('/api/admin/collections/drafts%2F2026'),
        );
      },
    );

    test('throws when Admin API list responses have the wrong shape', () async {
      const transport = StubAdminApiTransport(
        AdminApiResponse(
          statusCode: 200,
          body: <String, Object?>{'items': 'not-a-list'},
        ),
      );
      final controlPlane = AdminControlPlane(
        AdminApiClient(
          baseUrl: Uri.parse('http://localhost'),
          transport: transport,
        ),
      );

      await expectLater(
        controlPlane.listCollectionSchemas(),
        throwsA(
          isA<AdminApiException>().having(
            (error) => error.message,
            'message',
            contains('items'),
          ),
        ),
      );
    });

    test('restores and clears a browser session bearer token', () async {
      final transport = RecordingAdminApiTransport();
      final api = AdminApiClient(
        baseUrl: Uri.parse('http://localhost'),
        transport: transport,
      )..bearerToken = 'saved-token';
      await api.listCollectionSchemas();
      api.clearBearerToken();
      await api.listCollectionSchemas();

      expect(api.bearerToken, isNull);
      expect(
        transport.requests.map((request) => request.headers['authorization']),
        <String?>['Bearer saved-token', null],
      );
    });
  });
}

class StubAdminApiTransport extends AdminApiTransport {
  const StubAdminApiTransport(this.response);

  final AdminApiResponse response;

  @override
  Future<AdminApiResponse> send(AdminApiRequest request) async {
    return response;
  }
}

class RecordingAdminApiTransport extends AdminApiTransport {
  final List<AdminApiRequest> requests = <AdminApiRequest>[];

  @override
  Future<AdminApiResponse> send(AdminApiRequest request) async {
    requests.add(request);
    return const AdminApiResponse(
      statusCode: 200,
      body: <String, Object?>{'items': <Object?>[]},
    );
  }
}

class ServerAdminApiTransport extends AdminApiTransport {
  ServerAdminApiTransport(this.server);

  final ElmixServer server;
  final List<AdminApiRequest> requests = <AdminApiRequest>[];

  @override
  Future<AdminApiResponse> send(AdminApiRequest request) async {
    requests.add(request);
    final response = await server.handle(
      ElmixHttpRequest(
        method: _method(request.method),
        path: request.url.path,
        headers: request.headers,
        body: request.body,
      ),
    );
    return AdminApiResponse(
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  ElmixHttpRequestMethod _method(String method) {
    return ElmixHttpRequestMethod.values.firstWhere(
      (value) => value.value == method,
    );
  }
}

class MemoryStorageAdapter implements StorageAdapter {
  final Map<String, CollectionSchema> _schemas = <String, CollectionSchema>{};
  final Map<String, Map<String, Record>> _records =
      <String, Map<String, Record>>{};

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
    final recordToStore = record.id.value.isNotEmpty
        ? record
        : Record(
            collection: record.collection,
            id: RecordIdentifier(
              '${record.collection}_'
              '${(_records[record.collection]?.length ?? 0) + 1}',
            ),
            data: record.data,
          );
    _records.putIfAbsent(
      recordToStore.collection,
      () => <String, Record>{},
    )[recordToStore.id.value] = recordToStore;
    return recordToStore;
  }
}
