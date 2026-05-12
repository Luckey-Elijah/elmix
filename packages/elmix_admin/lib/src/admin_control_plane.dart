import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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
        accessRules: <CollectionOperation, AccessRule>{
          CollectionOperation.list: AccessRule('false'),
          CollectionOperation.view: AccessRule('false'),
          CollectionOperation.create: AccessRule('false'),
          CollectionOperation.update: AccessRule('false'),
          CollectionOperation.delete: AccessRule('false'),
        },
      ),
    );
  }

  String _passwordHash(String password) {
    const iterations = 120000;
    final salt = _randomBytes(16);
    final hash = _pbkdf2Sha256(
      password: utf8.encode(password),
      salt: salt,
      iterations: iterations,
      length: 32,
    );
    return [
      'pbkdf2-sha256',
      iterations,
      base64UrlEncode(salt),
      base64UrlEncode(hash),
    ].join(r'$');
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  List<int> _pbkdf2Sha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int length,
  }) {
    final hmac = Hmac(sha256, password);
    final blocks = <int>[];
    var blockIndex = 1;
    while (blocks.length < length) {
      final blockIndexBytes = ByteData(4)..setUint32(0, blockIndex);
      var block = hmac.convert([
        ...salt,
        for (var index = 0; index < blockIndexBytes.lengthInBytes; index += 1)
          blockIndexBytes.getUint8(index),
      ]).bytes;
      final output = List<int>.from(block);
      for (var round = 1; round < iterations; round += 1) {
        block = hmac.convert(block).bytes;
        for (var index = 0; index < output.length; index += 1) {
          output[index] ^= block[index];
        }
      }
      blocks.addAll(output);
      blockIndex += 1;
    }
    return blocks.take(length).toList();
  }
}
