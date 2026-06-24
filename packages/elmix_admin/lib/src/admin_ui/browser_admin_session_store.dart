import 'package:elmix_admin/src/admin_ui/admin_session_store.dart';
import 'package:web/web.dart' as web;

/// [AdminSessionStore] backed by tab-scoped browser session storage.
class BrowserAdminSessionStore implements AdminSessionStore {
  /// Key used for the Admin API bearer token.
  static const bearerTokenKey = 'elmix.admin.bearer-token';

  @override
  String? readBearerToken() =>
      web.window.sessionStorage.getItem(bearerTokenKey);

  @override
  void saveBearerToken(String token) {
    web.window.sessionStorage.setItem(bearerTokenKey, token);
  }

  @override
  void clearBearerToken() {
    web.window.sessionStorage.removeItem(bearerTokenKey);
  }
}
