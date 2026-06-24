/// Browser-session storage for an Admin API bearer token.
abstract class AdminSessionStore {
  /// Reads the stored bearer token, if the browser session has one.
  String? readBearerToken();

  /// Stores [token] for the current browser session.
  void saveBearerToken(String token);

  /// Removes any bearer token from the current browser session.
  void clearBearerToken();
}

/// In-memory [AdminSessionStore] useful for tests and non-browser adapters.
class MemoryAdminSessionStore implements AdminSessionStore {
  String? _token;

  @override
  String? readBearerToken() => _token;

  @override
  void saveBearerToken(String token) {
    _token = token;
  }

  @override
  void clearBearerToken() {
    _token = null;
  }
}
