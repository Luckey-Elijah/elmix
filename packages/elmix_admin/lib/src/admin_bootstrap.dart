import 'package:elmix_engine/elmix_engine.dart';

/// Trusted setup and recovery helper for Admin Account access.
class AdminBootstrap {
  /// Creates an admin bootstrap helper backed by [engine].
  const AdminBootstrap(this.engine);

  /// The engine used by trusted setup paths.
  final ElmixEngine engine;

  /// Creates an Admin Account in the internal admin collection.
  Future<Record> createAdminAccount({
    required String email,
    required String password,
  }) async {
    await _ensureAdminCollection();
    final admin = Record(
      collection: '_admins',
      id: RecordIdentifier(email),
      data: <String, Object?>{
        'email': email,
        'passwordHash': AuthPassword.hash(password),
      },
    );
    return engine
        .collection('_admins', context: RequestContext.system)
        .create(admin);
  }

  Future<void> _ensureAdminCollection() async {
    final existing = await engine.getCollectionSchema('_admins');
    if (existing != null) {
      return;
    }
    await engine.registerCollection(
      const CollectionSchema(
        name: '_admins',
        fields: <SchemaField>[
          SchemaField.recordIdentifier(),
          SchemaField(name: 'email', type: .email, required: true),
          SchemaField(
            name: 'passwordHash',
            type: .password,
            required: true,
          ),
        ],
        accessRules: <CollectionOperation, AccessRule>{
          .list: AccessRule('false'),
          .view: AccessRule('false'),
          .create: AccessRule('false'),
          .update: AccessRule('false'),
          .delete: AccessRule('false'),
        },
      ),
    );
  }
}
