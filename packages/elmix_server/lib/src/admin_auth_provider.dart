import 'package:elmix_engine/elmix_engine.dart';

/// Pluggable credential source for Admin Account authentication.
///
/// Implementations provide password-based Admin Account lookup without
/// coupling [ElmixServer] to a specific storage or configuration path.
abstract class AdminAuthProvider {
  /// Authenticates an Admin Account by [email] and [password].
  ///
  /// Returns the matching [AdminAccount] when credentials are valid, or
  /// `null` when they are not.
  Future<AdminAccount?> authenticateWithPassword({
    required String email,
    required String password,
  });

  /// Whether this provider has any Admin Accounts registered.
  ///
  /// Used by [ElmixServer] to determine whether admin session enforcement
  /// should be active even when no persistent `_admins` collection exists.
  bool get hasAccounts;
}

/// An in-memory [AdminAuthProvider] backed by a fixed list of
/// [ServerAdminAccount] credentials.
///
/// Useful for tests, bootstrap examples, and environments without a
/// persistent admin account store.
class InMemoryAdminAuthProvider implements AdminAuthProvider {
  /// Creates an in-memory admin auth provider from [accounts].
  const InMemoryAdminAuthProvider(this._accounts);

  final List<ServerAdminAccount> _accounts;

  @override
  Future<AdminAccount?> authenticateWithPassword({
    required String email,
    required String password,
  }) async {
    final match = _accounts.where(
      (candidate) => candidate.email == email && candidate.password == password,
    );
    if (match.isEmpty) return null;
    return AdminAccount(
      id: match.first.id,
      email: match.first.email,
    );
  }

  @override
  bool get hasAccounts => _accounts.isNotEmpty;
}
