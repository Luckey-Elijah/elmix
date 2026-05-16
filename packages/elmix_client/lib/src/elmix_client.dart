import 'dart:convert';
import 'dart:io';

/// Dynamic client entry point for an Elmix server.
class ElmixClient {
  /// Creates a client that targets [baseUrl].
  ElmixClient(this.baseUrl);

  /// The base URL for the Elmix server.
  final Uri baseUrl;
  String? _bearerToken;

  /// The bearer token used for authenticated requests, if one is configured.
  String? get bearerToken => _bearerToken;

  /// Updates the bearer token used for authenticated requests.
  set bearerToken(String token) {
    _bearerToken = token;
  }

  /// Creates a client for the collection named [name].
  CollectionClient collection(String name) {
    return CollectionClient._(this, name);
  }

  /// Clears the configured authentication state.
  void clearAuth() {
    _bearerToken = null;
  }

  Future<Object?> _send({
    required String method,
    required Uri uri,
    Object? body,
  }) async {
    final httpClient = HttpClient();
    try {
      final request = await httpClient.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      if (_bearerToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $_bearerToken',
        );
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      final decoded = text.trim().isEmpty ? null : jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ElmixClientException.fromResponse(
          statusCode: response.statusCode,
          body: decoded,
        );
      }
      return decoded;
    } finally {
      httpClient.close(force: true);
    }
  }
}

/// Dynamic collection client boundary.
class CollectionClient {
  const CollectionClient._(this._client, this.name);

  final ElmixClient _client;

  /// The collection targeted by this client.
  final String name;

  /// Returns the API endpoint for the collection or a specific [recordId].
  Uri endpoint([String? recordId]) {
    final path = recordId == null
        ? '/api/collections/$name/records'
        : '/api/collections/$name/records/$recordId';
    return _client.baseUrl.replace(path: path);
  }

  /// Authenticates an Auth Record by email and password.
  Future<AuthResult> authWithPassword({
    required String email,
    required String password,
  }) async {
    final body = await _client._send(
      method: 'POST',
      uri: _client.baseUrl.replace(
        path: '/api/collections/$name/auth-with-password',
      ),
      body: <String, Object?>{
        'email': email,
        'password': password,
      },
    );
    final result = AuthResult.fromJson(_jsonObject(body));
    _client.bearerToken = result.token;
    return result;
  }

  /// Creates a record in this collection.
  Future<ClientRecord> create(Map<String, Object?> record) async {
    final body = await _client._send(
      method: 'POST',
      uri: endpoint(),
      body: record,
    );
    return ClientRecord.fromJson(_jsonObject(body));
  }

  /// Lists records in this collection.
  Future<ClientRecordPage> list() async {
    final body = await _client._send(method: 'GET', uri: endpoint());
    return ClientRecordPage.fromJson(_jsonObject(body));
  }

  /// Views a record in this collection by exact [recordId].
  Future<ClientRecord> view(String recordId) async {
    final body = await _client._send(method: 'GET', uri: endpoint(recordId));
    return ClientRecord.fromJson(_jsonObject(body));
  }

  /// Updates a record in this collection by exact [recordId].
  Future<ClientRecord> update(
    String recordId,
    Map<String, Object?> record,
  ) async {
    final body = await _client._send(
      method: 'PATCH',
      uri: endpoint(recordId),
      body: record,
    );
    return ClientRecord.fromJson(_jsonObject(body));
  }

  /// Deletes a record in this collection by exact [recordId].
  Future<void> delete(String recordId) async {
    await _client._send(method: 'DELETE', uri: endpoint(recordId));
  }
}

/// Dynamic record returned by the Elmix client.
class ClientRecord {
  /// Creates a dynamic record.
  const ClientRecord({
    required this.collection,
    required this.id,
    required this.data,
  });

  /// Decodes a record from Public API JSON.
  factory ClientRecord.fromJson(Map<String, Object?> json) {
    return ClientRecord(
      collection: json['collection']! as String,
      id: json['id']! as String,
      data: _jsonObject(json['data']),
    );
  }

  /// Collection name.
  final String collection;

  /// Record identifier.
  final String id;

  /// Dynamic record data.
  final Map<String, Object?> data;
}

/// A page of dynamic records returned by the Elmix client.
class ClientRecordPage {
  /// Creates a dynamic record page.
  const ClientRecordPage({
    required this.page,
    required this.perPage,
    required this.totalItems,
    required this.items,
  });

  /// Decodes a record page from Public API JSON.
  factory ClientRecordPage.fromJson(Map<String, Object?> json) {
    final items = json['items'];
    return ClientRecordPage(
      page: json['page']! as int,
      perPage: json['perPage']! as int,
      totalItems: json['totalItems']! as int,
      items: items is List<Object?>
          ? items
                .map((item) => ClientRecord.fromJson(_jsonObject(item)))
                .toList()
          : const <ClientRecord>[],
    );
  }

  /// Current page number.
  final int page;

  /// Requested records per page.
  final int perPage;

  /// Total matching records.
  final int totalItems;

  /// Records on this page.
  final List<ClientRecord> items;
}

/// Result of authenticating an Auth Record.
class AuthResult {
  /// Creates an authentication result.
  const AuthResult({
    required this.token,
    required this.record,
  });

  /// Decodes an authentication result from Public API JSON.
  factory AuthResult.fromJson(Map<String, Object?> json) {
    return AuthResult(
      token: json['token']! as String,
      record: ClientRecord.fromJson(_jsonObject(json['record'])),
    );
  }

  /// Bearer token for future requests.
  final String token;

  /// Authenticated Auth Record.
  final ClientRecord record;
}

/// Error response returned by the Elmix Public API.
class ElmixClientException implements Exception {
  /// Creates a client exception.
  const ElmixClientException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  /// Decodes a client exception from Public API error JSON.
  factory ElmixClientException.fromResponse({
    required int statusCode,
    required Object? body,
  }) {
    final object = _jsonObject(body);
    final error = _jsonObject(object['error']);
    return ElmixClientException(
      statusCode: statusCode,
      code: error['code'] is String ? error['code']! as String : 'http_error',
      message: error['message'] is String ? error['message']! as String : '',
    );
  }

  /// HTTP response status code.
  final int statusCode;

  /// Stable API error code.
  final String code;

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'ElmixClientException($statusCode, $code): $message';
}

Map<String, Object?> _jsonObject(Object? value) {
  return value is Map<String, Object?> ? value : const <String, Object?>{};
}
