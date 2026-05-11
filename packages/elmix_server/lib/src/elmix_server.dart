import 'package:elmix_engine/elmix_engine.dart';

/// Server boundary around an [ElmixEngine].
///
/// A concrete HTTP implementation can be added here without leaking transport
/// details into the Engine.
class ElmixServer {
  /// Creates a server boundary backed by [engine].
  ElmixServer(
    this.engine, {
    List<ServerAdminAccount> adminAccounts = const <ServerAdminAccount>[],
  }) : _adminAccounts = adminAccounts;

  /// The engine exposed through this server boundary.
  final ElmixEngine engine;

  final List<ServerAdminAccount> _adminAccounts;
  final Map<String, AdminAccount> _adminSessions = <String, AdminAccount>{};

  /// Handles one HTTP-shaped Elmix request.
  Future<ElmixHttpResponse> handle(ElmixHttpRequest request) async {
    try {
      return await _handle(request);
    } on AuthorizationException catch (error) {
      return _error(
        statusCode: 403,
        code: 'forbidden',
        message: error.message,
      );
    } on CollectionSchemaException catch (error) {
      return _error(
        statusCode: 400,
        code: 'schema_error',
        message: error.message,
      );
    } on RecordValidationException catch (error) {
      return _error(
        statusCode: 400,
        code: 'record_error',
        message: error.message,
      );
    } on QueryExpressionException catch (error) {
      return _error(
        statusCode: 400,
        code: 'query_error',
        message: error.message,
      );
    }
  }

  Future<ElmixHttpResponse> _handle(ElmixHttpRequest request) async {
    if (request.pathSegments case ['api', ...final apiSegments]) {
      if (apiSegments case ['admin', ...final adminSegments]) {
        if (adminSegments case ['auth-with-password']) {
          if (request.method == 'POST') return _authenticateAdmin(request);
        }
        if (adminSegments case ['collections']) {
          final adminRequired = _requireAdminSession(request);
          if (adminRequired != null) {
            return adminRequired;
          }
          if (request.method == 'GET') {
            final schemas = await engine.listCollections();
            return ElmixHttpResponse.ok(<String, Object?>{
              'items': schemas.map(_schemaToJson).toList(),
            });
          }
          if (request.method == 'POST') {
            final schema = _schemaFromJson(request.body);
            await engine.registerCollection(schema);
            return ElmixHttpResponse.created(_schemaToJson(schema));
          }
        }

        if (adminSegments case ['collections', final collection]) {
          final adminRequired = _requireAdminSession(request);
          if (adminRequired != null) {
            return adminRequired;
          }

          if (request.method == 'GET') {
            final schema = await engine.getCollectionSchema(collection);
            if (schema == null) {
              return _notFound();
            }
            return ElmixHttpResponse.ok(_schemaToJson(schema));
          }
          if (request.method == 'PUT' || request.method == 'PATCH') {
            final schema = _schemaFromJson(request.body);
            await engine.updateCollectionSchema(schema);
            return ElmixHttpResponse.ok(_schemaToJson(schema));
          }
        }

        if (adminSegments case [
          'collections',
          final collection,
          'records',
        ]) {
          final adminRequired = _requireAdminSession(request);
          if (adminRequired != null) {
            return adminRequired;
          }
          return _handleRecordCollectionRoute(
            request: request,
            collection: collection,
          );
        }

        if (adminSegments case [
          'collections',
          final collection,
          'records',
          final id,
        ]) {
          final adminRequired = _requireAdminSession(request);
          if (adminRequired != null) {
            return adminRequired;
          }
          return _handleRecordRoute(
            request: request,
            collection: collection,
            id: RecordIdentifier(id),
          );
        }
      }

      if (apiSegments case ['collections', ...final collectionSegments]) {
        if (collectionSegments case [final collection, 'auth-with-password']) {
          if (request.method == 'POST') {
            return _authenticateAuthRecord(
              collection: collection,
              request: request,
            );
          }
          return _notFound();
        }

        if (collectionSegments case [final collection, 'records']) {
          return _handleRecordCollectionRoute(
            request: request,
            collection: collection,
          );
        }

        if (collectionSegments case [final collection, 'records', final id]) {
          return _handleRecordRoute(
            request: request,
            collection: collection,
            id: RecordIdentifier(id),
          );
        }
      }
    }

    return _notFound();
  }

  ElmixHttpResponse _authenticateAdmin(ElmixHttpRequest request) {
    final object = request.body is Map<String, Object?>
        ? request.body! as Map<String, Object?>
        : const <String, Object?>{};
    final email = object['email'];
    final password = object['password'];
    final account = _adminAccounts.where(
      (candidate) => candidate.email == email && candidate.password == password,
    );
    if (account.isEmpty) {
      return _error(
        statusCode: 401,
        code: 'invalid_credentials',
        message: 'Admin Account credentials are invalid.',
      );
    }

    final admin = AdminAccount(
      id: account.first.id,
      email: account.first.email,
    );
    final token = 'admin:${admin.id.value}';
    _adminSessions[token] = admin;
    return ElmixHttpResponse.ok(<String, Object?>{
      'token': token,
      'admin': <String, Object?>{
        'id': admin.id.value,
        'email': admin.email,
      },
    });
  }

  Future<ElmixHttpResponse> _authenticateAuthRecord({
    required String collection,
    required ElmixHttpRequest request,
  }) async {
    final schema = await engine.getCollectionSchema(collection);
    if (schema == null || !schema.isAuthCollection) {
      return _notFound();
    }

    final object = request.body is Map<String, Object?>
        ? request.body! as Map<String, Object?>
        : const <String, Object?>{};
    final email = object['email'];
    final password = object['password'];
    final page = await engine.collection(collection).list();
    final records = page.items.where(
      (record) =>
          record.data['email'] == email && record.data['password'] == password,
    );
    if (records.isEmpty) {
      return _error(
        statusCode: 401,
        code: 'invalid_credentials',
        message: 'Auth Record credentials are invalid.',
      );
    }

    final record = records.first;
    final identity = await engine.runAuthenticationAction(
      collection: collection,
      action: AuthenticationOperation.authenticate,
      run: () async => AuthRecordIdentity(
        collection: collection,
        id: record.id,
      ),
    );
    return ElmixHttpResponse.ok(<String, Object?>{
      'token': 'record:${identity.collection}:${identity.id.value}',
      'record': _recordToJson(record),
    });
  }

  Future<ElmixHttpResponse> _handleRecordCollectionRoute({
    required ElmixHttpRequest request,
    required String collection,
  }) async {
    if (request.method == 'GET') {
      final page = await engine
          .collection(
            collection,
            context: request.context,
          )
          .list();
      return ElmixHttpResponse.ok(_recordPageToJson(page));
    }
    if (request.method == 'POST') {
      final schema = await engine.getCollectionSchema(collection);
      final created = await engine
          .collection(
            collection,
            context: request.context,
          )
          .create(
            _recordFromJson(
              collection: collection,
              body: request.body,
              schema: schema,
            ),
          );
      return ElmixHttpResponse.created(_recordToJson(created));
    }
    return _notFound();
  }

  Future<ElmixHttpResponse> _handleRecordRoute({
    required ElmixHttpRequest request,
    required String collection,
    required RecordIdentifier id,
  }) async {
    final records = engine.collection(collection, context: request.context);
    if (request.method == 'GET') {
      final record = await records.get(id);
      if (record == null) {
        return _notFound();
      }
      return ElmixHttpResponse.ok(_recordToJson(record));
    }
    if (request.method == 'PATCH') {
      final existing = await records.get(id);
      if (existing == null) {
        return _notFound();
      }
      final schema = await engine.getCollectionSchema(collection);
      final updated = await records.update(
        _recordFromJson(
          collection: collection,
          id: id,
          body: request.body,
          schema: schema,
          existingData: existing.data,
        ),
      );
      return ElmixHttpResponse.ok(_recordToJson(updated));
    }
    if (request.method == 'PUT') {
      final schema = await engine.getCollectionSchema(collection);
      final updated = await records.update(
        _recordFromJson(
          collection: collection,
          id: id,
          body: request.body,
          schema: schema,
        ),
      );
      return ElmixHttpResponse.ok(_recordToJson(updated));
    }
    if (request.method == 'DELETE') {
      await records.delete(id);
      return const ElmixHttpResponse(statusCode: 204);
    }
    return _notFound();
  }

  ElmixHttpResponse? _requireAdminSession(ElmixHttpRequest request) {
    if (_adminAccounts.isEmpty || _adminFromBearer(request) != null) {
      return null;
    }
    return _error(
      statusCode: 401,
      code: 'admin_session_required',
      message: 'An Admin Account session is required.',
    );
  }

  AdminAccount? _adminFromBearer(ElmixHttpRequest request) {
    final token = request.bearerToken;
    if (token == null) {
      return null;
    }
    return _adminSessions[token];
  }

  ElmixHttpResponse _error({
    required int statusCode,
    required String code,
    required String message,
  }) {
    return ElmixHttpResponse(
      statusCode: statusCode,
      body: <String, Object?>{
        'error': <String, Object?>{
          'code': code,
          'message': message,
        },
      },
    );
  }

  ElmixHttpResponse _notFound() {
    return const ElmixHttpResponse(
      statusCode: 404,
      body: <String, Object?>{
        'error': <String, Object?>{
          'code': 'not_found',
          'message': 'No Elmix API route matched the request.',
        },
      },
    );
  }

  Map<String, Object?> _recordPageToJson(RecordPage page) {
    return <String, Object?>{
      'page': page.page,
      'perPage': page.perPage,
      'totalItems': page.totalItems,
      'items': page.items.map(_recordToJson).toList(),
    };
  }

  Map<String, Object?> _recordToJson(Record record) {
    return <String, Object?>{
      'collection': record.collection,
      'id': record.id.value,
      'data': _jsonValue(record.data),
    };
  }

  Record _recordFromJson({
    required String collection,
    required Object? body,
    required CollectionSchema? schema,
    RecordIdentifier id = const RecordIdentifier(''),
    Map<String, Object?> existingData = const <String, Object?>{},
  }) {
    final object = body is Map<String, Object?> ? body : <String, Object?>{};
    final bodyId = object['id'];
    final bodyData = object['data'];
    final decodedData = _decodeRecordData(
      bodyData is Map<String, Object?> ? bodyData : const <String, Object?>{},
      schema: schema,
    );
    return Record(
      collection: collection,
      id: id.value.isNotEmpty
          ? id
          : RecordIdentifier(bodyId is String ? bodyId : ''),
      data: <String, Object?>{
        ...existingData,
        ...decodedData,
      },
    );
  }

  Map<String, Object?> _decodeRecordData(
    Map<String, Object?> data, {
    required CollectionSchema? schema,
  }) {
    if (schema == null) {
      return data;
    }

    final dateFields = <String>{
      for (final field in schema.fields)
        if (field.type == FieldType.date) field.name,
    };
    return <String, Object?>{
      for (final entry in data.entries)
        entry.key: dateFields.contains(entry.key)
            ? _decodeDateField(entry.key, entry.value)
            : entry.value,
    };
  }

  Object? _decodeDateField(String field, Object? value) {
    if (value == null || value is DateTime) {
      return value;
    }
    if (value is String) {
      try {
        return DateTime.parse(value);
      } on FormatException {
        throw RecordValidationException(
          'Field "$field" must be an ISO-8601 date string.',
        );
      }
    }
    return value;
  }

  Object? _jsonValue(Object? value) {
    return switch (value) {
      final DateTime date => date.toUtc().toIso8601String(),
      final Map<String, Object?> map => <String, Object?>{
        for (final entry in map.entries) entry.key: _jsonValue(entry.value),
      },
      final List<Object?> list => list.map(_jsonValue).toList(),
      _ => value,
    };
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
      systemRole: systemRole is String
          ? _fieldSystemRole(systemRole)
          : FieldSystemRole.none,
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
}

/// Admin Account credentials known to the server boundary.
class ServerAdminAccount {
  /// Creates a server-side Admin Account credential.
  const ServerAdminAccount({
    required this.id,
    required this.email,
    required this.password,
  });

  /// Stable Admin Account identifier.
  final AdminAccountIdentifier id;

  /// Admin Account email address.
  final String email;

  /// Password accepted by the server for this Admin Account.
  final String password;
}

/// Transport-independent representation of an HTTP request.
class ElmixHttpRequest {
  /// Creates an HTTP-shaped request for the Elmix server.
  const ElmixHttpRequest({
    required this.method,
    required this.path,
    this.body,
    this.headers = const <String, String>{},
  });

  /// The uppercase HTTP method.
  final String method;

  /// The request path.
  final String path;

  /// The decoded JSON body, when present.
  final Object? body;

  /// Request headers.
  final Map<String, String> headers;

  /// Bearer token from the Authorization header, when present.
  String? get bearerToken {
    final authorization = headers['authorization'] ?? headers['Authorization'];
    const prefix = 'Bearer ';
    if (authorization == null || !authorization.startsWith(prefix)) {
      return null;
    }
    return authorization.substring(prefix.length);
  }

  /// The Engine request context represented by this HTTP request.
  RequestContext get context {
    final token = bearerToken;
    if (token != null) {
      final parts = token.split(':');
      if (parts case ['record', final collection, final id]) {
        return RequestContext(
          authRecord: AuthRecordIdentity(
            collection: collection,
            id: RecordIdentifier(id),
          ),
        );
      }
    }

    final authCollection = headers['x-elmix-auth-collection'];
    final authId = headers['x-elmix-auth-id'];
    if (authCollection == null || authId == null) {
      return RequestContext.anonymous;
    }
    return RequestContext(
      authRecord: AuthRecordIdentity(
        collection: authCollection,
        id: RecordIdentifier(authId),
      ),
    );
  }

  /// The path split into decoded segments.
  List<String> get pathSegments {
    return Uri(
      path: path,
    ).pathSegments.where((segment) => segment.isNotEmpty).toList();
  }
}

/// Transport-independent representation of an HTTP response.
class ElmixHttpResponse {
  /// Creates an HTTP-shaped response from the Elmix server.
  const ElmixHttpResponse({
    required this.statusCode,
    this.body,
  });

  /// Creates a successful JSON response.
  const ElmixHttpResponse.ok(this.body) : statusCode = 200;

  /// Creates a successful creation JSON response.
  const ElmixHttpResponse.created(this.body) : statusCode = 201;

  /// The HTTP status code.
  final int statusCode;

  /// The decoded JSON response body.
  final Object? body;
}
