import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:elmix_engine/src/record.dart';
import 'package:pointycastle/export.dart';

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
    this.isSystem = false,
  });

  /// Anonymous request context.
  static const anonymous = RequestContext();

  /// Trusted framework context for control-plane use cases.
  static const system = RequestContext(isSystem: true);

  /// The authenticated application record, when present.
  final AuthRecordIdentity? authRecord;

  /// Whether this request comes from trusted framework code.
  final bool isSystem;
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

/// Hashes and verifies stored credentials.
///
/// Implement this interface to use a different credential algorithm while
/// preserving Elmix's password-field and Auth Record behavior.
abstract class CredentialHasher {
  /// Creates a credential hasher.
  const CredentialHasher();

  /// Returns a self-describing stored credential hash for [password].
  String hash(String password);

  /// Whether [stored] is a credential hash understood by this hasher.
  bool isHash(Object? stored);

  /// Verifies [password] against [stored].
  bool verify({
    required String password,
    required Object? stored,
  });
}

/// PBKDF2-HMAC-SHA256 [CredentialHasher] used by Elmix Core v0 by default.
///
/// Stored hashes include their algorithm, iteration count, salt, and derived
/// key so future hashers can recognize or migrate their own formats.
class Pbkdf2CredentialHasher implements CredentialHasher {
  /// Creates the default PBKDF2 credential hasher.
  const Pbkdf2CredentialHasher();

  static const _legacySha256Prefix = 'sha256:';
  static const _pbkdf2Sha256Prefix = r'pbkdf2-sha256$';
  static const _pbkdf2Iterations = 120000;
  static const _saltLength = 16;
  static const _hashLength = 32;

  @override
  String hash(String password) {
    final salt = _randomBytes(_saltLength);
    final hash = _pbkdf2Sha256(
      password: utf8.encode(password),
      salt: salt,
      iterations: _pbkdf2Iterations,
      length: _hashLength,
    );
    return <Object>[
      'pbkdf2-sha256',
      _pbkdf2Iterations,
      base64UrlEncode(salt),
      base64UrlEncode(hash),
    ].join(r'$');
  }

  @override
  bool isHash(Object? stored) {
    return stored is String &&
        (stored.startsWith(_legacySha256Prefix) ||
            stored.startsWith(_pbkdf2Sha256Prefix));
  }

  @override
  bool verify({
    required String password,
    required Object? stored,
  }) {
    if (stored is! String) {
      return false;
    }
    if (stored.startsWith(_legacySha256Prefix)) {
      final digest = sha256.convert(utf8.encode(password));
      return _constantTimeEquals(
        utf8.encode(stored),
        utf8.encode('$_legacySha256Prefix$digest'),
      );
    }
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts.first != 'pbkdf2-sha256') {
      return false;
    }
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1) {
      return false;
    }
    try {
      final salt = base64Url.decode(parts[2]);
      final expected = base64Url.decode(parts[3]);
      if (expected.isEmpty) {
        return false;
      }
      final actual = _pbkdf2Sha256(
        password: utf8.encode(password),
        salt: salt,
        iterations: iterations,
        length: expected.length,
      );
      return _constantTimeEquals(actual, expected);
    } on FormatException {
      return false;
    }
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  Uint8List _pbkdf2Sha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int length,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(
        Pbkdf2Parameters(
          Uint8List.fromList(salt),
          iterations,
          length,
        ),
      );
    return derivator.process(Uint8List.fromList(password));
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

/// Compatibility helpers for the default [Pbkdf2CredentialHasher].
///
/// Prefer configuring a [CredentialHasher] when constructing an engine.
class AuthPassword {
  static const CredentialHasher _defaultHasher = Pbkdf2CredentialHasher();

  /// Returns a stored password hash using Elmix's default credential hasher.
  static String hash(String password) => _defaultHasher.hash(password);

  /// Whether [stored] is recognized by Elmix's default credential hasher.
  static bool isHash(Object? stored) => _defaultHasher.isHash(stored);

  /// Verifies [password] using Elmix's default credential hasher.
  static bool verify({
    required String password,
    required Object? stored,
  }) {
    return _defaultHasher.verify(password: password, stored: stored);
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
