import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
