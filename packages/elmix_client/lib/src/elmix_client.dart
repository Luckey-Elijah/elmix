import 'dart:convert';
import 'dart:io';

/// Dynamic client entry point for an Elmix server.
class ElmixClient {
  /// Creates a client that targets [baseUrl].
  ElmixClient(this.baseUrl, {ElmixClientTransport? transport})
    : _transport = transport ?? IoElmixClientTransport();

  /// The base URL for the Elmix server.
  final Uri baseUrl;
  final ElmixClientTransport _transport;
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

  Future<ElmixClientResponse> _send(ElmixClientRequest request) {
    return _transport.send(request);
  }
}

/// Dynamic collection client boundary.
class CollectionClient {
  const CollectionClient._(this._client, this.name);

  final ElmixClient _client;

  /// The collection targeted by this client.
  final String name;

  /// Returns the API endpoint for the collection or a specific [recordId].
  Uri endpoint([String? recordId, Map<String, Object?> query = const {}]) {
    final path = recordId == null
        ? '/api/collections/$name/records'
        : '/api/collections/$name/records/$recordId';
    return _client.baseUrl.replace(
      path: path,
      queryParameters: _toQueryParameters(query),
    );
  }

  /// Returns the Auth Record email/password endpoint for this collection.
  Uri authWithPasswordEndpoint() {
    return _client.baseUrl.replace(
      path: '/api/collections/$name/auth-with-password',
    );
  }

  /// Opens a fluent list query for this collection.
  // ignore: use_to_and_as_if_applicable, collection list queries are domain API.
  DynamicListQuery list() {
    return DynamicListQuery._(this);
  }

  /// Fetches one dynamic record by [id].
  Future<DynamicRecord> view(String id) async {
    final response = await _client._send(
      ElmixClientRequest(
        method: 'GET',
        url: endpoint(id),
        headers: _client._headers,
      ),
    );
    return DynamicRecord.fromJson(_expectObject(response));
  }

  /// Creates a dynamic record from [data].
  Future<DynamicRecord> create(Map<String, Object?> data) async {
    final response = await _client._send(
      ElmixClientRequest(
        method: 'POST',
        url: endpoint(),
        headers: _client._headers,
        body: _recordBody(data),
      ),
    );
    return DynamicRecord.fromJson(_expectObject(response));
  }

  /// Updates an existing dynamic record by [id].
  Future<DynamicRecord> update(String id, Map<String, Object?> data) async {
    final response = await _client._send(
      ElmixClientRequest(
        method: 'PATCH',
        url: endpoint(id),
        headers: _client._headers,
        body: <String, Object?>{'data': data},
      ),
    );
    return DynamicRecord.fromJson(_expectObject(response));
  }

  /// Deletes one dynamic record by [id].
  Future<void> delete(String id) async {
    final response = await _client._send(
      ElmixClientRequest(
        method: 'DELETE',
        url: endpoint(id),
        headers: _client._headers,
      ),
    );
    _expectEmpty(response);
  }

  /// Authenticates an Auth Record with [email] and [password].
  Future<AuthRecordSession> authWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _client._send(
      ElmixClientRequest(
        method: 'POST',
        url: authWithPasswordEndpoint(),
        headers: _client._headers,
        body: <String, Object?>{
          'email': email,
          'password': password,
        },
      ),
    );
    final session = AuthRecordSession.fromJson(_expectObject(response));
    _client.bearerToken = session.token;
    return session;
  }

  Map<String, String>? _toQueryParameters(Map<String, Object?> query) {
    if (query.isEmpty) {
      return null;
    }
    return <String, String>{'query': jsonEncode(query)};
  }

  Map<String, Object?> _recordBody(Map<String, Object?> data) {
    final id = data['id'];
    return <String, Object?>{
      if (id is String) 'id': id,
      'data': <String, Object?>{
        for (final entry in data.entries)
          if (entry.key != 'id') entry.key: entry.value,
      },
    };
  }
}

/// Authenticated Auth Record session returned by the Public API.
class AuthRecordSession {
  /// Creates an Auth Record session.
  const AuthRecordSession({
    required this.token,
    required this.record,
  });

  /// Creates an Auth Record session from an Elmix response body.
  factory AuthRecordSession.fromJson(Map<String, Object?> json) {
    return AuthRecordSession(
      token: json['token']! as String,
      record: DynamicRecord.fromJson(json['record']),
    );
  }

  /// Bearer token for subsequent Public API requests.
  final String token;

  /// Authenticated Auth Record.
  final DynamicRecord record;
}

/// Fluent builder for dynamic collection list queries.
class DynamicListQuery {
  const DynamicListQuery._(
    this._collection, {
    this.filters = const <Map<String, Object?>>[],
    this.sort = const <Map<String, Object?>>[],
    this.pagination = const <String, Object?>{'page': 1, 'perPage': 30},
  });

  final CollectionClient _collection;

  /// Field filters. Multiple filters are combined with implicit conjunction.
  final List<Map<String, Object?>> filters;

  /// Sort instructions in the order they were added.
  final List<Map<String, Object?>> sort;

  /// Page/per-page pagination settings.
  final Map<String, Object?> pagination;

  /// Adds an equality filter.
  DynamicListQuery eq(String field, Object? value) {
    return _filter(field, 'equals', value);
  }

  /// Adds an inequality filter.
  DynamicListQuery neq(String field, Object? value) {
    return _filter(field, 'notEquals', value);
  }

  /// Adds a greater-than filter.
  DynamicListQuery gt(String field, Object? value) {
    return _filter(field, 'greaterThan', value);
  }

  /// Adds a greater-than-or-equal filter.
  DynamicListQuery gte(String field, Object? value) {
    return _filter(field, 'greaterThanOrEquals', value);
  }

  /// Adds a less-than filter.
  DynamicListQuery lt(String field, Object? value) {
    return _filter(field, 'lessThan', value);
  }

  /// Adds a less-than-or-equal filter.
  DynamicListQuery lte(String field, Object? value) {
    return _filter(field, 'lessThanOrEquals', value);
  }

  /// Sorts ascending by [field].
  DynamicListQuery asc(String field) {
    return _sort(field, 'ascending');
  }

  /// Sorts descending by [field].
  DynamicListQuery desc(String field) {
    return _sort(field, 'descending');
  }

  /// Uses one-based [number] and optional [perPage] pagination.
  DynamicListQuery page(int number, {int perPage = 30}) {
    return DynamicListQuery._(
      _collection,
      filters: filters,
      sort: sort,
      pagination: <String, Object?>{'page': number, 'perPage': perPage},
    );
  }

  /// Sends the built list query to the Elmix server.
  Future<DynamicRecordPage> send() async {
    final query = _toQuery();
    final response = await _collection._client._send(
      ElmixClientRequest(
        method: 'GET',
        url: _collection.endpoint(null, query),
        query: query,
        headers: _collection._client._headers,
      ),
    );
    return DynamicRecordPage.fromJson(_expectObject(response));
  }

  DynamicListQuery _filter(String field, String operator, Object? value) {
    return DynamicListQuery._(
      _collection,
      filters: <Map<String, Object?>>[
        ...filters,
        <String, Object?>{
          'field': field,
          'operator': operator,
          'value': value,
        },
      ],
      sort: sort,
      pagination: pagination,
    );
  }

  DynamicListQuery _sort(String field, String direction) {
    return DynamicListQuery._(
      _collection,
      filters: filters,
      sort: <Map<String, Object?>>[
        ...sort,
        <String, Object?>{
          'field': field,
          'direction': direction,
        },
      ],
      pagination: pagination,
    );
  }

  Map<String, Object?> _toQuery() {
    return <String, Object?>{
      if (filters.isNotEmpty) 'filters': filters,
      if (sort.isNotEmpty) 'sort': sort,
      'pagination': pagination,
    };
  }
}

/// A page of dynamic collection records.
class DynamicRecordPage {
  /// Creates a dynamic record page.
  const DynamicRecordPage({
    required this.items,
    required this.page,
    required this.perPage,
    required this.totalItems,
  });

  /// Creates a page from an Elmix Public API response body.
  factory DynamicRecordPage.fromJson(Map<String, Object?> json) {
    final items = json['items'];
    return DynamicRecordPage(
      items: items is List<Object?>
          ? items.map(DynamicRecord.fromJson).toList()
          : const <DynamicRecord>[],
      page: json['page']! as int,
      perPage: json['perPage']! as int,
      totalItems: json['totalItems']! as int,
    );
  }

  /// Records in this page.
  final List<DynamicRecord> items;

  /// One-based page number.
  final int page;

  /// Requested page size.
  final int perPage;

  /// Total matching records.
  final int totalItems;
}

/// Identifiable dynamic collection record.
class DynamicRecord {
  /// Creates a dynamic record.
  const DynamicRecord({
    required this.collection,
    required this.id,
    required this.data,
  });

  /// Creates a dynamic record from an Elmix Public API response item.
  factory DynamicRecord.fromJson(Object? value) {
    final json = value is Map<String, Object?> ? value : <String, Object?>{};
    final data = json['data'];
    final id = json['id']! as String;
    return DynamicRecord(
      collection: json['collection']! as String,
      id: id,
      data: <String, Object?>{
        if (data is Map<String, Object?>) ...data,
        'id': id,
      },
    );
  }

  /// Collection that owns this record.
  final String collection;

  /// Record Identifier.
  final String id;

  /// Dynamic record data, including `id`.
  final Map<String, Object?> data;
}

/// A transport request emitted by the dynamic client.
class ElmixClientRequest {
  /// Creates a transport request.
  const ElmixClientRequest({
    required this.method,
    required this.url,
    this.query = const <String, Object?>{},
    this.headers = const <String, String>{},
    this.body,
  });

  /// Uppercase HTTP method.
  final String method;

  /// Fully resolved request URL.
  final Uri url;

  /// Structured Elmix query payload represented in URL query parameters.
  final Map<String, Object?> query;

  /// Request headers.
  final Map<String, String> headers;

  /// JSON request body, when present.
  final Object? body;
}

/// A transport response returned to the dynamic client.
class ElmixClientResponse {
  /// Creates a transport response.
  const ElmixClientResponse({
    required this.statusCode,
    this.body,
  });

  /// HTTP status code.
  final int statusCode;

  /// Decoded JSON response body.
  final Object? body;
}

/// Transport boundary used by the dynamic client.
class ElmixClientTransport {
  /// Creates a transport boundary.
  const ElmixClientTransport();

  /// Sends [request] and returns a decoded response.
  Future<ElmixClientResponse> send(ElmixClientRequest request) {
    throw UnimplementedError('ElmixClientTransport.send');
  }
}

/// Default `dart:io` transport for the dynamic client.
class IoElmixClientTransport implements ElmixClientTransport {
  /// Creates a `dart:io` transport.
  IoElmixClientTransport({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  @override
  Future<ElmixClientResponse> send(ElmixClientRequest request) async {
    final httpRequest = await _httpClient.openUrl(request.method, request.url);
    for (final header in request.headers.entries) {
      httpRequest.headers.set(header.key, header.value);
    }
    if (request.body != null) {
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.write(jsonEncode(request.body));
    }

    final httpResponse = await httpRequest.close();
    final text = await utf8.decoder.bind(httpResponse).join();
    return ElmixClientResponse(
      statusCode: httpResponse.statusCode,
      body: text.isEmpty ? null : jsonDecode(text),
    );
  }
}

Map<String, Object?> _expectObject(ElmixClientResponse response) {
  final body = response.body;
  if (body is Map<String, Object?> && response.statusCode < 400) {
    return body;
  }
  throw ElmixClientException(response);
}

void _expectEmpty(ElmixClientResponse response) {
  if (response.statusCode < 400) {
    return;
  }
  throw ElmixClientException(response);
}

/// Error returned when an Elmix client request is unsuccessful.
class ElmixClientException implements Exception {
  /// Creates a client exception from [response].
  const ElmixClientException(this.response);

  /// The unsuccessful response.
  final ElmixClientResponse response;

  /// HTTP status code returned by the server.
  int get statusCode => response.statusCode;

  /// Elmix-owned error code, when the response uses the standard envelope.
  String? get code => _errorField('code');

  /// Elmix-owned error message, when the response uses the standard envelope.
  String? get message => _errorField('message');

  @override
  String toString() {
    return 'ElmixClientException: request failed with '
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

extension on ElmixClient {
  Map<String, String> get _headers {
    final token = bearerToken;
    if (token == null) {
      return const <String, String>{};
    }
    return <String, String>{'authorization': 'Bearer $token'};
  }
}
