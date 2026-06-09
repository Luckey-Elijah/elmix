import 'package:elmix_engine/elmix_engine.dart';

/// Admin-facing application boundary backed by the Admin API.
class AdminControlPlane {
  /// Creates an Admin Control Plane using [api].
  const AdminControlPlane(this.api);

  /// Admin API client used by this control plane.
  final AdminApiClient api;

  /// Authenticates an Admin Account through the Admin API.
  Future<AdminSession> login({
    required String email,
    required String password,
  }) {
    return api.authWithPassword(email: email, password: password);
  }

  /// Lists Collection Schemas through the Admin API.
  Future<List<CollectionSchema>> listCollectionSchemas() {
    return api.listCollectionSchemas();
  }

  /// Creates a Collection Schema through the Admin API.
  Future<CollectionSchema> createCollectionSchema(CollectionSchema schema) {
    return api.createCollectionSchema(schema);
  }

  /// Updates a Collection Schema through the Admin API.
  Future<CollectionSchema> updateCollectionSchema(CollectionSchema schema) {
    return api.updateCollectionSchema(schema);
  }

  /// Deletes a Collection Schema through the Admin API.
  Future<void> deleteCollectionSchema(String collection) {
    return api.deleteCollectionSchema(collection);
  }

  /// Creates a field by updating its owning Collection Schema.
  Future<CollectionSchema> createSchemaField({
    required String collection,
    required SchemaField field,
  }) async {
    final schema = await api.getCollectionSchema(collection);
    return api.updateCollectionSchema(
      CollectionSchema(
        name: schema.name,
        isAuthCollection: schema.isAuthCollection,
        fields: <SchemaField>[...schema.fields, field],
        accessRules: schema.accessRules,
      ),
    );
  }

  /// Updates a field by replacing it in its owning Collection Schema.
  Future<CollectionSchema> updateSchemaField({
    required String collection,
    required SchemaField field,
  }) async {
    final schema = await api.getCollectionSchema(collection);
    return api.updateCollectionSchema(
      CollectionSchema(
        name: schema.name,
        isAuthCollection: schema.isAuthCollection,
        fields: <SchemaField>[
          for (final existing in schema.fields)
            if (existing.name == field.name) field else existing,
        ],
        accessRules: schema.accessRules,
      ),
    );
  }

  /// Deletes a field by updating its owning Collection Schema.
  Future<CollectionSchema> deleteSchemaField({
    required String collection,
    required String field,
  }) async {
    final schema = await api.getCollectionSchema(collection);
    return api.updateCollectionSchema(
      CollectionSchema(
        name: schema.name,
        isAuthCollection: schema.isAuthCollection,
        fields: <SchemaField>[
          for (final existing in schema.fields)
            if (existing.name != field) existing,
        ],
        accessRules: schema.accessRules,
      ),
    );
  }

  /// Updates Access Rules by updating their owning Collection Schema.
  Future<CollectionSchema> updateAccessRules({
    required String collection,
    required Map<CollectionOperation, AccessRule> accessRules,
  }) async {
    final schema = await api.getCollectionSchema(collection);
    return api.updateCollectionSchema(
      CollectionSchema(
        name: schema.name,
        isAuthCollection: schema.isAuthCollection,
        fields: schema.fields,
        accessRules: accessRules,
      ),
    );
  }

  /// Lists records for [collection] through the Admin API.
  Future<RecordPage> listRecords(String collection) {
    return api.listRecords(collection);
  }

  /// Creates a record through the Admin API.
  Future<Record> createRecord(Record record) {
    return api.createRecord(record);
  }

  /// Views a record through the Admin API.
  Future<Record> viewRecord({
    required String collection,
    required RecordIdentifier id,
  }) {
    return api.viewRecord(collection: collection, id: id);
  }

  /// Updates a record through the Admin API.
  Future<Record> updateRecord(Record record) {
    return api.updateRecord(record);
  }

  /// Deletes a record through the Admin API.
  Future<void> deleteRecord({
    required String collection,
    required RecordIdentifier id,
  }) {
    return api.deleteRecord(collection: collection, id: id);
  }
}

/// Client for the Elmix Admin API.
class AdminApiClient {
  /// Creates an Admin API client.
  AdminApiClient({
    required this.baseUrl,
    required this.transport,
  });

  /// Base URL for the Elmix server.
  final Uri baseUrl;

  /// Transport used to send Admin API requests.
  final AdminApiTransport transport;

  String? _bearerToken;

  /// Bearer token used for Admin API requests, if authenticated.
  String? get bearerToken => _bearerToken;

  /// Authenticates an Admin Account by email and password.
  Future<AdminSession> authWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/admin/auth-with-password',
      body: <String, Object?>{
        'email': email,
        'password': password,
      },
    );
    final session = AdminSession.fromJson(_expectObject(response));
    _bearerToken = session.token;
    return session;
  }

  /// Lists Collection Schemas.
  Future<List<CollectionSchema>> listCollectionSchemas() async {
    final response = await _send(method: 'GET', path: '/api/admin/collections');
    final object = _expectObject(response);
    final items = object['items'];
    if (items is! List<Object?>) {
      throw AdminApiException(
        response,
        message: 'Admin API response field "items" must be a list.',
      );
    }
    return items.map(_schemaFromJson).toList();
  }

  /// Fetches one Collection Schema.
  Future<CollectionSchema> getCollectionSchema(String collection) async {
    final response = await _send(
      method: 'GET',
      pathSegments: _adminCollectionPathSegments(collection),
    );
    return _schemaFromJson(_expectObject(response));
  }

  /// Creates a Collection Schema.
  Future<CollectionSchema> createCollectionSchema(
    CollectionSchema schema,
  ) async {
    final response = await _send(
      method: 'POST',
      path: '/api/admin/collections',
      body: _schemaToJson(schema),
    );
    return _schemaFromJson(_expectObject(response));
  }

  /// Updates a Collection Schema.
  Future<CollectionSchema> updateCollectionSchema(
    CollectionSchema schema,
  ) async {
    final response = await _send(
      method: 'PUT',
      pathSegments: _adminCollectionPathSegments(schema.name),
      body: _schemaToJson(schema),
    );
    return _schemaFromJson(_expectObject(response));
  }

  /// Deletes a Collection Schema.
  Future<void> deleteCollectionSchema(String collection) async {
    final response = await _send(
      method: 'DELETE',
      pathSegments: _adminCollectionPathSegments(collection),
    );
    _expectEmpty(response);
  }

  /// Lists records in [collection].
  Future<RecordPage> listRecords(String collection) async {
    final response = await _send(
      method: 'GET',
      pathSegments: _adminCollectionPathSegments(
        collection,
        const <String>['records'],
      ),
    );
    return _recordPageFromJson(_expectObject(response));
  }

  /// Creates [record].
  Future<Record> createRecord(Record record) async {
    final response = await _send(
      method: 'POST',
      pathSegments: _adminCollectionPathSegments(
        record.collection,
        const <String>['records'],
      ),
      body: _recordToJson(record),
    );
    return _recordFromJson(_expectObject(response));
  }

  /// Views one record.
  Future<Record> viewRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    final response = await _send(
      method: 'GET',
      pathSegments: _adminCollectionPathSegments(
        collection,
        <String>['records', id.value],
      ),
    );
    return _recordFromJson(_expectObject(response));
  }

  /// Updates [record].
  Future<Record> updateRecord(Record record) async {
    final response = await _send(
      method: 'PATCH',
      pathSegments: _adminCollectionPathSegments(
        record.collection,
        <String>['records', record.id.value],
      ),
      body: _recordToJson(record),
    );
    return _recordFromJson(_expectObject(response));
  }

  /// Deletes one record.
  Future<void> deleteRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    final response = await _send(
      method: 'DELETE',
      pathSegments: _adminCollectionPathSegments(
        collection,
        <String>['records', id.value],
      ),
    );
    _expectEmpty(response);
  }

  Future<AdminApiResponse> _send({
    required String method,
    String? path,
    List<String>? pathSegments,
    Object? body,
  }) {
    assert(
      path != null || pathSegments != null,
      'Admin API requests must provide a path or pathSegments.',
    );
    assert(
      path == null || pathSegments == null,
      'Admin API requests must not provide both path and pathSegments.',
    );
    return transport.send(
      AdminApiRequest(
        method: method,
        url: pathSegments == null
            ? baseUrl.replace(path: path)
            : baseUrl.replace(pathSegments: pathSegments),
        headers: <String, String>{
          if (_bearerToken != null) 'authorization': 'Bearer $_bearerToken',
        },
        body: body,
      ),
    );
  }

  List<String> _adminCollectionPathSegments(
    String collection, [
    List<String> suffix = const <String>[],
  ]) {
    return <String>['api', 'admin', 'collections', collection, ...suffix];
  }
}

/// Authenticated Admin Account session returned by the Admin API.
class AdminSession {
  /// Creates an Admin Account session.
  const AdminSession({
    required this.token,
    required this.admin,
  });

  /// Creates a session from Admin API JSON.
  factory AdminSession.fromJson(Map<String, Object?> json) {
    return AdminSession(
      token: json['token']! as String,
      admin: AdminAccountView.fromJson(json['admin']),
    );
  }

  /// Bearer token for subsequent Admin API requests.
  final String token;

  /// Authenticated Admin Account.
  final AdminAccountView admin;
}

/// Admin Account view returned by the Admin API.
class AdminAccountView {
  /// Creates an Admin Account view.
  const AdminAccountView({
    required this.id,
    required this.email,
  });

  /// Creates an Admin Account view from Admin API JSON.
  factory AdminAccountView.fromJson(Object? value) {
    final json = value is Map<String, Object?> ? value : <String, Object?>{};
    return AdminAccountView(
      id: json['id']! as String,
      email: json['email']! as String,
    );
  }

  /// Stable Admin Account identifier.
  final String id;

  /// Admin Account email address.
  final String email;
}

/// Transport request emitted by the Admin API client.
class AdminApiRequest {
  /// Creates an Admin API request.
  const AdminApiRequest({
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    this.body,
  });

  /// Uppercase HTTP method.
  final String method;

  /// Fully resolved Admin API URL.
  final Uri url;

  /// Request headers.
  final Map<String, String> headers;

  /// JSON request body, when present.
  final Object? body;
}

/// Transport response returned to the Admin API client.
class AdminApiResponse {
  /// Creates an Admin API response.
  const AdminApiResponse({
    required this.statusCode,
    this.body,
  });

  /// HTTP status code returned by the Admin API.
  final int statusCode;

  /// Decoded response body.
  final Object? body;
}

/// Transport boundary used by the Admin API client.
class AdminApiTransport {
  /// Creates an Admin API transport.
  const AdminApiTransport();

  /// Sends [request] and returns a decoded response.
  Future<AdminApiResponse> send(AdminApiRequest request) {
    throw UnimplementedError('AdminApiTransport.send');
  }
}

/// Error returned when an Admin API request is unsuccessful.
class AdminApiException implements Exception {
  /// Creates an Admin API exception.
  const AdminApiException(this.response, {String? message})
    : _message = message;

  /// The unsuccessful response.
  final AdminApiResponse response;

  final String? _message;

  /// HTTP status code returned by the Admin API.
  int get statusCode => response.statusCode;

  /// Elmix-owned error code, when present.
  String? get code => _errorField('code');

  /// Elmix-owned error message, when present.
  String? get message => _message ?? _errorField('message');

  @override
  String toString() {
    return 'AdminApiException: request failed with '
        'status $statusCode'
        '${code == null ? '' : ' ($code)'}'
        '${message == null ? '' : ': $message'}';
  }

  String? _errorField(String name) {
    final body = response.body;
    if (body is! Map<String, Object?>) {
      return null;
    }
    final error = body['error'];
    if (error is! Map<String, Object?>) {
      return null;
    }
    final value = error[name];
    return value is String ? value : null;
  }
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

CollectionSchema _schemaFromJson(Object? value) {
  final json = value is Map<String, Object?> ? value : <String, Object?>{};
  final fields = json['fields'];
  final accessRules = json['accessRules'];
  return CollectionSchema(
    name: json['name']! as String,
    isAuthCollection: json['isAuthCollection'] == true,
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

SchemaField _fieldFromJson(Object? value) {
  final json = value is Map<String, Object?> ? value : <String, Object?>{};
  final removable = json['removable'];
  final systemRole = json['systemRole'];
  return SchemaField(
    name: json['name']! as String,
    type: FieldType.values.firstWhere(
      (type) => type.name == json['type']! as String,
    ),
    required: json['required'] == true,
    removable: removable is! bool || removable,
    systemRole: systemRole is String
        ? FieldSystemRole.values.firstWhere((role) => role.name == systemRole)
        : .none,
    targetCollection: json['targetCollection'] as String?,
  );
}

Map<String, Object?> _recordToJson(Record record) {
  return <String, Object?>{
    'id': record.id.value,
    'data': _jsonValue(record.data),
  };
}

Record _recordFromJson(Object? value) {
  final json = value is Map<String, Object?> ? value : <String, Object?>{};
  final data = json['data'];
  return Record(
    collection: json['collection']! as String,
    id: RecordIdentifier(json['id']! as String),
    data: data is Map<String, Object?> ? data : const <String, Object?>{},
  );
}

RecordPage _recordPageFromJson(Map<String, Object?> json) {
  final items = json['items'];
  return RecordPage(
    items: items is List<Object?>
        ? items.map(_recordFromJson).toList()
        : const <Record>[],
    page: json['page']! as int,
    perPage: json['perPage']! as int,
    totalItems: json['totalItems']! as int,
  );
}

CollectionOperation _collectionOperation(String name) {
  return CollectionOperation.values.firstWhere(
    (operation) => operation.name == name,
  );
}

Object? _jsonValue(Object? value) => switch (value) {
  final DateTime date => date.toUtc().toIso8601String(),
  final Map<String, Object?> map => <String, Object?>{
    for (final entry in map.entries) entry.key: _jsonValue(entry.value),
  },
  final List<Object?> list => list.map(_jsonValue).toList(),
  _ => value,
};

Map<String, Object?> _expectObject(AdminApiResponse response) {
  final body = response.body;
  if (body is Map<String, Object?> && response.statusCode < 400) {
    return body;
  }
  throw AdminApiException(response);
}

void _expectEmpty(AdminApiResponse response) {
  if (response.statusCode < 400) {
    return;
  }
  throw AdminApiException(response);
}
