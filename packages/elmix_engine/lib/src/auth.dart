import 'package:elmix_engine/src/record.dart';

/// A record from an auth-enabled collection that can authenticate to APIs.
class AuthRecord extends Record {
  /// Creates an authentication-capable application record.
  const AuthRecord({
    required super.collection,
    required super.id,
    required super.data,
  });
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
