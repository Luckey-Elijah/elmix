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
