import 'dart:convert';
import 'dart:math';

import 'package:elmix_engine/elmix_engine.dart';

/// Server boundary around an [ElmixEngine].
///
/// A concrete HTTP implementation can be added here without leaking transport
/// details into the Engine.
class ElmixServer {
  /// Creates a server boundary backed by [engine].
  ElmixServer(
    this.engine, {
    AdminAuthProvider? adminAuth,
  }) : _adminAuth = adminAuth ?? EngineAdminAuthProvider(engine);

  /// The engine exposed through this server boundary.
  final ElmixEngine engine;

  final AdminAuthProvider _adminAuth;
  final _adminSessions = <String, AdminAccount>{};
  final _authRecordSessions = <String, AuthRecordIdentity>{};

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
        final response = await _handleAdmin(request, adminSegments);
        if (response != null) return response;
      }
      if (apiSegments case ['collections', ...final collectionSegments]) {
        final response = await _handleCollection(request, collectionSegments);
        if (response != null) return response;
      }
    }

    return _notFound();
  }

  Future<ElmixHttpResponse?> _handleCollection(
    ElmixHttpRequest request,
    List<String> collectionSegments,
  ) async {
    if (collectionSegments case [final collection, 'auth-with-password']) {
      if (request.method == .post) {
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
    return null;
  }

  Future<ElmixHttpResponse?> _handleAdmin(
    ElmixHttpRequest request,
    List<String> adminSegments,
  ) async {
    if (adminSegments case ['auth-with-password']) {
      if (request.method == .post) return _authenticateAdmin(request);
    }
    if (adminSegments case ['collections']) {
      final adminRequired = await _requireAdminSession(request);
      if (adminRequired != null) {
        return adminRequired;
      }
      if (request.method == .get) {
        final schemas = await engine.listCollections();
        return ElmixHttpResponse.ok(<String, Object?>{
          'items': schemas.map(_schemaToJson).toList(),
        });
      }
      if (request.method == .post) {
        final schema = _schemaFromJson(request.body);
        await engine.registerCollection(schema);
        return ElmixHttpResponse.created(_schemaToJson(schema));
      }
    }

    if (adminSegments case ['collections', final collection]) {
      final adminRequired = await _requireAdminSession(request);
      if (adminRequired != null) {
        return adminRequired;
      }

      if (request.method == .get) {
        final schema = await engine.getCollectionSchema(collection);
        if (schema == null) {
          return _notFound();
        }
        return ElmixHttpResponse.ok(_schemaToJson(schema));
      }
      if (request.method == .put || request.method == .patch) {
        final schema = _schemaFromJson(request.body);
        await engine.updateCollectionSchema(schema);
        return ElmixHttpResponse.ok(_schemaToJson(schema));
      }
      if (request.method == .delete) {
        if (_isFrameworkOwnedInternalCollection(collection)) {
          return _error(
            statusCode: 403,
            code: 'forbidden',
            message: 'Framework-owned internal collections cannot be deleted.',
          );
        }
        await engine.deleteCollectionSchema(collection);
        return const ElmixHttpResponse(statusCode: 204);
      }
    }

    if (adminSegments case ['collections', final collection, 'records']) {
      final adminRequired = await _requireAdminSession(request);
      if (adminRequired != null) {
        return adminRequired;
      }
      return _handleRecordCollectionRoute(
        request: request,
        collection: collection,
        controlPlane: engine.controlPlane,
      );
    }

    if (adminSegments case [
      'collections',
      final collection,
      'records',
      final id,
    ]) {
      final adminRequired = await _requireAdminSession(request);
      if (adminRequired != null) return adminRequired;
      return _handleRecordRoute(
        request: request,
        collection: collection,
        id: RecordIdentifier(id),
        controlPlane: engine.controlPlane,
      );
    }
    return null;
  }

  Future<ElmixHttpResponse> _authenticateAdmin(ElmixHttpRequest request) async {
    final object = request.body is Map<String, Object?>
        ? request.body! as Map<String, Object?>
        : const <String, Object?>{};
    final email = object['email'];
    final password = object['password'];
    final admin = await _adminAuth.authenticateWithPassword(
      email: email is String ? email : '',
      password: password is String ? password : '',
    );
    if (admin == null) {
      return _error(
        statusCode: 401,
        code: 'invalid_credentials',
        message: 'Admin Account credentials are invalid.',
      );
    }

    final token = _issueBearerToken();
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
    final object = request.body is Map<String, Object?>
        ? request.body! as Map<String, Object?>
        : const <String, Object?>{};
    final email = object['email'] is String ? object['email']! as String : '';
    final password = object['password'] is String
        ? object['password']! as String
        : '';

    late final AuthRecord record;
    try {
      record = await engine.authenticateAuthRecordWithPassword(
        collection: collection,
        email: email,
        password: password,
      );
    } on AuthRecordAuthenticationException catch (error) {
      return _error(
        statusCode: 401,
        code: 'invalid_credentials',
        message: error.message,
      );
    } on CollectionSchemaException {
      return _notFound();
    }

    final token = _issueAuthRecordToken(
      AuthRecordIdentity(
        collection: record.collection,
        id: record.id,
      ),
    );
    return ElmixHttpResponse.ok(<String, Object?>{
      'token': token,
      'record': _recordToJson(record, includePasswordFields: false),
    });
  }

  Future<ElmixHttpResponse> _handleRecordCollectionRoute({
    required ElmixHttpRequest request,
    required String collection,
    RequestContext? context,
    ControlPlane? controlPlane,
  }) async {
    final requestContext = context ?? _contextForRequest(request);
    final records =
        controlPlane?.collection(collection) ??
        engine.collection(
          collection,
          context: requestContext,
        );
    if (request.method == .get) {
      final page = await records.list(
        query: await _queryExpressionFromRequest(request, collection),
      );
      return ElmixHttpResponse.ok(_recordPageToJson(page));
    }
    if (request.method == .post) {
      final schema = await engine.getCollectionSchema(collection);
      final created = await records.create(
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
    RequestContext? context,
    ControlPlane? controlPlane,
  }) async {
    final requestContext = context ?? _contextForRequest(request);
    final records =
        controlPlane?.collection(collection) ??
        engine.collection(
          collection,
          context: requestContext,
        );
    if (request.method == .get) {
      final record = await records.get(id);
      if (record == null) {
        return _notFound();
      }
      return ElmixHttpResponse.ok(_recordToJson(record));
    }
    if (request.method == .patch) {
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
    if (request.method == .put) {
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
    if (request.method == .delete) {
      await records.delete(id);
      return const ElmixHttpResponse(statusCode: 204);
    }
    return _notFound();
  }

  Future<ElmixHttpResponse?> _requireAdminSession(
    ElmixHttpRequest request,
  ) async {
    if (!await _hasAdminAccounts() || _adminFromBearer(request) != null) {
      return null;
    }
    return _error(
      statusCode: 401,
      code: 'admin_session_required',
      message: 'An Admin Account session is required.',
    );
  }

  Future<bool> _hasAdminAccounts() async {
    return _adminAuth.hasAccounts();
  }

  AdminAccount? _adminFromBearer(ElmixHttpRequest request) {
    final token = request.bearerToken;
    if (token == null) {
      return null;
    }
    return _adminSessions[token];
  }

  RequestContext _contextForRequest(ElmixHttpRequest request) {
    final token = request.bearerToken;
    if (token != null) {
      final identity = _authRecordSessions[token];
      if (identity != null) {
        return RequestContext(authRecord: identity);
      }
      return RequestContext.anonymous;
    }

    return request.headerContext;
  }

  ElmixHttpResponse _error({
    required int statusCode,
    required String code,
    required String message,
  }) {
    return ElmixHttpResponse(
      statusCode: statusCode,
      body: <String, Object?>{
        'error': <String, Object?>{'code': code, 'message': message},
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

  // TODO(elijah): move to RecordPage
  Map<String, Object?> _recordPageToJson(RecordPage page) {
    return <String, Object?>{
      'page': page.page,
      'perPage': page.perPage,
      'totalItems': page.totalItems,
      'items': page.items.map(_recordToJson).toList(),
    };
  }

  // TODO(elijah): make part of Record class..
  // TODO(elijah): override in subclasses where needed
  Map<String, Object?> _recordToJson(
    Record record, {
    bool includePasswordFields = true,
  }) {
    return <String, Object?>{
      'collection': record.collection,
      'id': record.id.value,
      'data': _jsonValue(
        includePasswordFields
            ? record.data
            : <String, Object?>{
                for (final entry in record.data.entries)
                  if (!engine.credentialHasher.isHash(entry.value))
                    entry.key: entry.value,
              },
      ),
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
    if (schema == null) return data;

    final dateFields = <String>{
      for (final field in schema.fields)
        if (field.type == .date) field.name,
    };
    return <String, Object?>{
      for (final entry in data.entries)
        entry.key: dateFields.contains(entry.key)
            ? _decodeDateField(entry.key, entry.value)
            : entry.value,
    };
  }

  Object? _decodeDateField(String field, Object? value) {
    if (value == null || value is DateTime) return value;
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

  Object? _jsonValue(Object? value) => switch (value) {
    final DateTime date => date.toUtc().toIso8601String(),
    final Map<String, Object?> map => <String, Object?>{
      for (final entry in map.entries) entry.key: _jsonValue(entry.value),
    },
    final List<Object?> list => list.map(_jsonValue).toList(),
    _ => value,
  };

  // TODO(elijah): move this to CollectionSchema
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

  // TODO(elijah): move this to SchemaField
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

  // TODO(elijah): move this to the CollectionSchema class
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

  // TODO(elijah): move this to the SchemaField class
  SchemaField _fieldFromJson(Object? body) {
    final object = body is Map<String, Object?> ? body : <String, Object?>{};
    final removable = object['removable'];
    final systemRole = object['systemRole'];
    return SchemaField(
      name: object['name']! as String,
      type: _fieldType(object['type']! as String),
      required: object['required'] == true,
      removable: removable is! bool || removable,
      systemRole: systemRole is String ? _fieldSystemRole(systemRole) : .none,
      targetCollection: object['targetCollection'] as String?,
    );
  }

  FieldType _fieldType(String name) {
    return .values.firstWhere((type) => type.name == name);
  }

  FieldSystemRole _fieldSystemRole(String name) {
    return FieldSystemRole.values.firstWhere((role) => role.name == name);
  }

  CollectionOperation _collectionOperation(String name) {
    return CollectionOperation.values.firstWhere(
      (operation) => operation.name == name,
    );
  }

  bool _isFrameworkOwnedInternalCollection(String collection) {
    return const <String>{'_admins'}.contains(collection);
  }

  Future<QueryExpression> _queryExpressionFromRequest(
    ElmixHttpRequest request,
    String collection,
  ) async {
    final encoded = request.queryParameters['query'];
    if (encoded == null) {
      return const QueryExpression();
    }
    final decoded = jsonDecode(encoded);
    final object = decoded is Map<String, Object?>
        ? decoded
        : const <String, Object?>{};
    final schema = await engine.getCollectionSchema(collection);
    return QueryExpression(
      filters: _queryFilters(object['filters'], schema: schema),
      sort: _querySort(object['sort']),
      pagination: _queryPagination(object['pagination']),
    );
  }

  List<QueryFilter> _queryFilters(
    Object? value, {
    required CollectionSchema? schema,
  }) {
    if (value is! List<Object?>) {
      return const <QueryFilter>[];
    }
    final dateFields = <String>{
      for (final field in schema?.fields ?? const <SchemaField>[])
        if (field.type == FieldType.date) field.name,
    };
    return value.map((item) {
      final object = item is Map<String, Object?>
          ? item
          : const <String, Object?>{};
      final field = object['field']! as String;
      return QueryFilter(
        field: field,
        operator: _queryOperator(object['operator']! as String),
        value: dateFields.contains(field)
            ? _decodeDateField(field, object['value'])
            : object['value'],
      );
    }).toList();
  }

  List<QuerySort> _querySort(Object? value) {
    if (value is! List<Object?>) {
      return const <QuerySort>[];
    }
    return value.map((item) {
      final object = item is Map<String, Object?>
          ? item
          : const <String, Object?>{};
      return QuerySort(
        field: object['field']! as String,
        direction: _sortDirection(object['direction']! as String),
      );
    }).toList();
  }

  QueryPagination _queryPagination(Object? value) {
    if (value is! Map<String, Object?>) {
      return const QueryPagination();
    }
    return QueryPagination(
      page: value['page'] is int ? value['page']! as int : 1,
      perPage: value['perPage'] is int ? value['perPage']! as int : 30,
    );
  }

  QueryOperator _queryOperator(String name) {
    return QueryOperator.values.firstWhere((operator) => operator.name == name);
  }

  SortDirection _sortDirection(String name) {
    return SortDirection.values.firstWhere(
      (direction) => direction.name == name,
    );
  }

  String _issueAuthRecordToken(AuthRecordIdentity authRecord) {
    final token = _issueBearerToken();
    _authRecordSessions[token] = authRecord;
    return token;
  }

  String _issueBearerToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
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

/// Credential source for Admin Account authentication.
abstract class AdminAuthProvider {
  /// Returns the authenticated Admin Account, if the credentials are valid.
  Future<AdminAccount?> authenticateWithPassword({
    required String email,
    required String password,
  });

  /// Whether this source contains at least one Admin Account.
  Future<bool> hasAccounts();
}

/// In-memory [AdminAuthProvider] for tests and bootstrap examples.
class InMemoryAdminAuthProvider implements AdminAuthProvider {
  /// Creates a provider from [accounts].
  const InMemoryAdminAuthProvider(this.accounts);

  /// Credentials known to this provider.
  final List<ServerAdminAccount> accounts;

  @override
  Future<AdminAccount?> authenticateWithPassword({
    required String email,
    required String password,
  }) async {
    final account = accounts.where(
      (candidate) => candidate.email == email && candidate.password == password,
    );
    if (account.isEmpty) return null;
    return AdminAccount(id: account.first.id, email: account.first.email);
  }

  @override
  Future<bool> hasAccounts() async => accounts.isNotEmpty;
}

/// [AdminAuthProvider] backed by the framework-owned Admin Account records.
class EngineAdminAuthProvider implements AdminAuthProvider {
  /// Creates a provider that reads Admin Accounts through [engine].
  EngineAdminAuthProvider(this.engine);

  /// Engine used to access the internal Admin Account collection.
  final ElmixEngine engine;

  @override
  Future<AdminAccount?> authenticateWithPassword({
    required String email,
    required String password,
  }) async {
    final schema = await engine.getCollectionSchema('_admins');
    if (schema == null) return null;
    final page = await engine.controlPlane
        .collection('_admins')
        .list(
          query: QueryExpression(
            filters: <QueryFilter>[
              QueryFilter(field: 'email', operator: .equals, value: email),
            ],
          ),
        );
    for (final record in page.items) {
      if (engine.credentialHasher.verify(
        password: password,
        stored: record.data['passwordHash'],
      )) {
        return AdminAccount(
          id: AdminAccountIdentifier(record.id.value),
          email: record.data['email']! as String,
        );
      }
    }
    return null;
  }

  @override
  Future<bool> hasAccounts() async {
    final schema = await engine.getCollectionSchema('_admins');
    if (schema == null) return false;
    final page = await engine.controlPlane
        .collection('_admins')
        .list(
          query: const QueryExpression(pagination: QueryPagination(perPage: 1)),
        );
    return page.totalItems > 0;
  }
}

/// HTTP request methods accepted by the Elmix server boundary.
enum ElmixHttpRequestMethod {
  /// Requests a representation of the target resource.
  get('GET'),

  /// Requests headers for the target resource without a response body.
  head('HEAD'),

  /// Submits data to the target resource.
  post('POST'),

  /// Replaces the target resource with the request payload.
  put('PUT'),

  /// Deletes the target resource.
  delete('DELETE'),

  /// Establishes a tunnel to the target resource.
  connect('CONNECT'),

  /// Requests communication options for the target resource.
  options('OPTIONS'),

  /// Performs a message loop-back test along the request path.
  trace('TRACE'),

  /// Applies a partial modification to the target resource.
  patch('PATCH')
  ;

  /// Creates an HTTP request method with its wire value.
  const ElmixHttpRequestMethod(this.value);

  /// Uppercase method value sent over HTTP.
  final String value;
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
  final ElmixHttpRequestMethod method;

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

  /// The Engine request context represented by explicit auth headers.
  RequestContext get headerContext {
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
    return _uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  }

  /// The decoded URL query parameters.
  Map<String, String> get queryParameters {
    return _uri.queryParameters;
  }

  Uri get _uri {
    return Uri.parse(path);
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
