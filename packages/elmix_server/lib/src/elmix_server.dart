import 'dart:convert';

import 'package:elmix_engine/elmix_engine.dart';

/// Server boundary around an [ElmixEngine].
///
/// A concrete HTTP implementation can be added here without leaking transport
/// details into the Engine.
class ElmixServer {
  /// Creates a server boundary backed by [engine].
  ElmixServer(this.engine);

  /// The engine exposed through this server boundary.
  final ElmixEngine engine;
  final Map<String, AuthRecordIdentity> _authSessions =
      <String, AuthRecordIdentity>{};

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
    final segments = request.pathSegments;
    if (_matchesAdminCollectionsRoute(segments)) {
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

    if (_matchesAdminCollectionRoute(segments)) {
      final collection = segments[3];
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

    if (_matchesAdminRecordsCollectionRoute(segments)) {
      return _handleRecordCollectionRoute(
        request: request,
        collection: segments[3],
      );
    }

    if (_matchesAdminRecordRoute(segments)) {
      return _handleRecordRoute(
        request: request,
        collection: segments[3],
        id: RecordIdentifier(segments[5]),
      );
    }

    if (_matchesAuthWithPasswordRoute(segments)) {
      return _handleAuthWithPasswordRoute(
        request: request,
        collection: segments[2],
      );
    }

    if (_matchesRecordsCollectionRoute(segments)) {
      return _handleRecordCollectionRoute(
        request: request,
        collection: segments[2],
      );
    }

    if (_matchesRecordRoute(segments)) {
      return _handleRecordRoute(
        request: request,
        collection: segments[2],
        id: RecordIdentifier(segments[4]),
      );
    }

    return _notFound();
  }

  Future<ElmixHttpResponse> _handleRecordCollectionRoute({
    required ElmixHttpRequest request,
    required String collection,
  }) async {
    if (request.method == 'GET') {
      final page = await engine
          .collection(
            collection,
            context: _requestContext(request),
          )
          .list(query: _queryExpressionFromRequest(request));
      return ElmixHttpResponse.ok(_recordPageToJson(page));
    }
    if (request.method == 'POST') {
      final schema = await engine.getCollectionSchema(collection);
      final created = await engine
          .collection(
            collection,
            context: _requestContext(request),
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
    final records = engine.collection(
      collection,
      context: _requestContext(request),
    );
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

  Future<ElmixHttpResponse> _handleAuthWithPasswordRoute({
    required ElmixHttpRequest request,
    required String collection,
  }) async {
    if (request.method != 'POST') {
      return _notFound();
    }
    final schema = await engine.getCollectionSchema(collection);
    if (schema == null || !schema.isAuthCollection) {
      return _notFound();
    }

    final body = request.body is Map<String, Object?>
        ? request.body! as Map<String, Object?>
        : const <String, Object?>{};
    final email = body['email'];
    final password = body['password'];
    if (email is! String || password is! String) {
      return _error(
        statusCode: 400,
        code: 'auth_error',
        message: 'Email and password are required.',
      );
    }

    final page = await engine
        .collection(collection)
        .list(
          query: QueryExpression(
            filters: <QueryFilter>[
              QueryFilter(
                field: 'email',
                operator: QueryOperator.equals,
                value: email,
              ),
              QueryFilter(
                field: 'password',
                operator: QueryOperator.equals,
                value: password,
              ),
            ],
            pagination: const QueryPagination(perPage: 1),
          ),
        );
    if (page.items.isEmpty) {
      return _error(
        statusCode: 401,
        code: 'invalid_credentials',
        message: 'Auth Record credentials are invalid.',
      );
    }

    final record = page.items.single;
    final authRecord = await engine.runAuthenticationAction(
      collection: collection,
      action: AuthenticationOperation.authenticate,
      run: () async => AuthRecordIdentity(
        collection: collection,
        id: record.id,
      ),
    );
    final token = _issueAuthToken(authRecord);
    return ElmixHttpResponse.ok(<String, Object?>{
      'token': token,
      'record': _recordToJson(record),
    });
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

  bool _matchesRecordsCollectionRoute(List<String> segments) {
    return segments.length == 4 &&
        segments[0] == 'api' &&
        segments[1] == 'collections' &&
        segments[3] == 'records';
  }

  bool _matchesRecordRoute(List<String> segments) {
    return segments.length == 5 &&
        segments[0] == 'api' &&
        segments[1] == 'collections' &&
        segments[3] == 'records';
  }

  bool _matchesAuthWithPasswordRoute(List<String> segments) {
    return segments.length == 4 &&
        segments[0] == 'api' &&
        segments[1] == 'collections' &&
        segments[3] == 'auth-with-password';
  }

  bool _matchesAdminCollectionsRoute(List<String> segments) {
    return segments.length == 3 &&
        segments[0] == 'api' &&
        segments[1] == 'admin' &&
        segments[2] == 'collections';
  }

  bool _matchesAdminCollectionRoute(List<String> segments) {
    return segments.length == 4 &&
        segments[0] == 'api' &&
        segments[1] == 'admin' &&
        segments[2] == 'collections';
  }

  bool _matchesAdminRecordsCollectionRoute(List<String> segments) {
    return segments.length == 5 &&
        segments[0] == 'api' &&
        segments[1] == 'admin' &&
        segments[2] == 'collections' &&
        segments[4] == 'records';
  }

  bool _matchesAdminRecordRoute(List<String> segments) {
    return segments.length == 6 &&
        segments[0] == 'api' &&
        segments[1] == 'admin' &&
        segments[2] == 'collections' &&
        segments[4] == 'records';
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

  QueryExpression _queryExpressionFromRequest(ElmixHttpRequest request) {
    final encoded = request.queryParameters['query'];
    if (encoded == null) {
      return const QueryExpression();
    }
    final decoded = jsonDecode(encoded);
    final object = decoded is Map<String, Object?>
        ? decoded
        : const <String, Object?>{};
    return QueryExpression(
      filters: _queryFilters(object['filters']),
      sort: _querySort(object['sort']),
      pagination: _queryPagination(object['pagination']),
    );
  }

  List<QueryFilter> _queryFilters(Object? value) {
    if (value is! List<Object?>) {
      return const <QueryFilter>[];
    }
    return value.map((item) {
      final object = item is Map<String, Object?>
          ? item
          : const <String, Object?>{};
      return QueryFilter(
        field: object['field']! as String,
        operator: _queryOperator(object['operator']! as String),
        value: object['value'],
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

  String _issueAuthToken(AuthRecordIdentity authRecord) {
    final tokenData =
        '${authRecord.collection}:${authRecord.id.value}:'
        '${_authSessions.length}';
    final token = base64Url.encode(
      utf8.encode(tokenData),
    );
    _authSessions[token] = authRecord;
    return token;
  }

  RequestContext _requestContext(ElmixHttpRequest request) {
    final authorization = request.headers['authorization'];
    if (authorization != null && authorization.startsWith('Bearer ')) {
      final token = authorization.substring('Bearer '.length);
      final authRecord = _authSessions[token];
      if (authRecord != null) {
        return RequestContext(authRecord: authRecord);
      }
    }
    return request.context;
  }
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

  /// The Engine request context represented by this HTTP request.
  RequestContext get context {
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
