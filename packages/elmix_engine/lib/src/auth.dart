import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:elmix_engine/src/record.dart';

/// Auth Record identity attached to one Engine request.
class AuthRecordIdentity {
  /// Creates an authenticated application record identity.
  const AuthRecordIdentity({
    required this.collection,
    required this.id,
  });

  /// The Auth Collection that owns this identity.
  final String collection;

  /// The authenticated record identifier.
  final RecordIdentifier id;
}

/// Request-scoped Engine execution context.
class RequestContext {
  /// Creates request context for Engine use cases.
  const RequestContext({
    this.authRecord,
  });

  /// Anonymous request context.
  static const anonymous = RequestContext();

  /// The authenticated application record, when present.
  final AuthRecordIdentity? authRecord;
}

/// A record from an auth-enabled collection that can authenticate to APIs.
class AuthRecord extends Record {
  /// Creates an authentication-capable application record.
  const AuthRecord({
    required super.collection,
    required super.id,
    required super.data,
  });
}

/// Thrown when Auth Record credentials are not valid for an Auth Collection.
class AuthRecordAuthenticationException implements Exception {
  /// Creates an authentication failure with a human-readable [message].
  const AuthRecordAuthenticationException(this.message);

  /// Describes why authentication failed.
  final String message;

  @override
  String toString() => 'AuthRecordAuthenticationException: $message';
}

/// Password hashing helpers for Auth Records and password fields.
class AuthPassword {
  static const _prefix = 'sha256:';

  /// Returns a stored password hash for [password].
  static String hash(String password) {
    final digest = sha256.convert(utf8.encode(password));
    return '$_prefix$digest';
  }

  /// Whether [stored] is a password hash produced by [hash].
  static bool isHash(Object? stored) {
    return stored is String && stored.startsWith(_prefix);
  }

  /// Verifies [password] against a stored hash.
  static bool verify({
    required String password,
    required Object? stored,
  }) {
    return stored is String && stored == hash(password);
  }
}

/// Stable identity for an admin account.
class AdminAccountIdentifier {
  /// Creates an admin account identifier.
  const AdminAccountIdentifier(this.value);

  /// The persisted identifier value.
  final String value;
}

/// Operator identity for managing the Elmix control plane.
class AdminAccount {
  /// Creates an admin account.
  const AdminAccount({
    required this.id,
    required this.email,
  });

  /// The admin account identifier.
  final AdminAccountIdentifier id;

  /// The admin account email address.
  final String email;
}
