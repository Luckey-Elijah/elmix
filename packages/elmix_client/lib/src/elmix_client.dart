/// Dynamic client entry point for an Elmix server.
final class ElmixClient {
  ElmixClient(this.baseUrl);

  final Uri baseUrl;
  String? _bearerToken;

  String? get bearerToken => _bearerToken;

  CollectionClient collection(String name) {
    return CollectionClient._(this, name);
  }

  void setBearerToken(String token) {
    _bearerToken = token;
  }

  void clearAuth() {
    _bearerToken = null;
  }
}

/// Dynamic collection client boundary.
final class CollectionClient {
  const CollectionClient._(this._client, this.name);

  final ElmixClient _client;
  final String name;

  Uri endpoint([String? recordId]) {
    final path = recordId == null
        ? '/api/collections/$name/records'
        : '/api/collections/$name/records/$recordId';
    return _client.baseUrl.replace(path: path);
  }
}
