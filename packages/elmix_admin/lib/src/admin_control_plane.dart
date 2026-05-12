import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:elmix_engine/elmix_engine.dart';

/// Boundary for the Admin Control Plane.
class AdminControlPlane {
  /// Creates an admin control plane backed by [engine].
  const AdminControlPlane(this.engine);

  /// The engine managed by this admin boundary.
  final ElmixEngine engine;

  /// Creates an Admin Account in the built-in admin auth collection.
  Future<Record> createAdminAccount({
    required String email,
    required String password,
  }) async {
    await _ensureAdminCollection();
    final admin = AuthRecord(
      collection: '_admins',
      id: RecordIdentifier(email),
      data: <String, Object?>{
        'email': email,
        'passwordHash': _passwordHash(password),
      },
    );
    return engine.collection('_admins').create(admin);
  }

  Future<void> _ensureAdminCollection() async {
    final existing = await engine.getCollectionSchema('_admins');
    if (existing != null) {
      return;
    }
    await engine.registerCollection(
      const CollectionSchema.auth(
        name: '_admins',
        fields: <SchemaField>[
          SchemaField.recordIdentifier(),
          SchemaField(name: 'email', type: FieldType.email, required: true),
          SchemaField(
            name: 'passwordHash',
            type: FieldType.password,
            required: true,
          ),
        ],
        accessRules: <CollectionOperation, AccessRule>{},
      ),
    );
  }

  String _passwordHash(String password) {
    return 'sha256:${sha256.convert(utf8.encode(password))}';
  }
}
