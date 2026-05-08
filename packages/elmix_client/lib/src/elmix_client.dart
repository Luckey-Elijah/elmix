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
}
