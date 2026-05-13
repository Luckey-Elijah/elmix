import 'package:elmix_engine/elmix_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Collection Schema contracts', () {
    test('represent the initial field set and system field semantics', () {
      expect(
        FieldType.values,
        containsAll(<FieldType>[
          .text,
          .number,
          .bool,
          .date,
          .email,
          .password,
          .select,
          .relation,
          .json,
        ]),
      );

      final fields = CollectionSchema.defaultFields();

      expect(
        fields.map((field) => field.name),
        containsAll(['id', 'created', 'updated']),
      );
      expect(
        fields.firstWhere((field) => field.name == 'id').systemRole,
        FieldSystemRole.recordIdentifier,
      );
      expect(
        fields.firstWhere((field) => field.name == 'id').removable,
        isFalse,
      );
      expect(
        fields.firstWhere((field) => field.name == 'created').systemRole,
        FieldSystemRole.created,
      );
      expect(
        fields.firstWhere((field) => field.name == 'created').removable,
        isTrue,
      );
      expect(
        fields.firstWhere((field) => field.name == 'updated').systemRole,
        FieldSystemRole.updated,
      );
      expect(
        fields.firstWhere((field) => field.name == 'updated').removable,
        isTrue,
      );
    });

    test('represent auth records without requiring a users collection', () {
      const schema = CollectionSchema.auth(
        name: 'members',
        fields: <SchemaField>[
          SchemaField(name: 'email', type: .email, required: true),
          SchemaField(
            name: 'password',
            type: .password,
            required: true,
          ),
        ],
        accessRules: <CollectionOperation, AccessRule>{},
      );

      const authRecord = AuthRecord(
        collection: 'members',
        id: RecordIdentifier('member_1'),
        data: <String, Object?>{'email': 'one@example.com'},
      );
      const adminAccount = AdminAccount(
        id: AdminAccountIdentifier('admin_1'),
        email: 'admin@example.com',
      );

      expect(schema.isAuthCollection, isTrue);
      expect(authRecord.collection, 'members');
      expect(authRecord.collection, isNot('users'));
      expect(adminAccount.id.value, 'admin_1');
      expect(adminAccount.email, 'admin@example.com');
    });
  });

  group('Storage Adapter contracts', () {
    test(
      'accept query expressions without transport or database details',
      () async {
        final storage = MemoryStorageAdapter();
        const schema = CollectionSchema(
          name: 'posts',
          fields: <SchemaField>[
            SchemaField.recordIdentifier(),
            SchemaField(name: 'published', type: .bool),
          ],
          accessRules: <CollectionOperation, AccessRule>{},
        );
        const query = QueryExpression(
          filters: <QueryFilter>[
            QueryFilter(field: 'published', operator: .equals, value: true),
          ],
          sort: [QuerySort(field: 'created', direction: .descending)],
          pagination: QueryPagination(page: 2, perPage: 10),
        );

        await storage.putCollectionSchema(schema);
        await storage.putRecord(
          const Record(
            collection: 'posts',
            id: RecordIdentifier('post_1'),
            data: <String, Object?>{'published': true},
          ),
        );

        final records = await storage.listRecords(
          collection: 'posts',
          query: query,
        );

        expect(await storage.getCollectionSchema('posts'), schema);
        expect(storage.lastQuery, query);
        expect(records.items.single.id.value, 'post_1');
      },
    );
  });

  group('Public extensibility', () {
    test('allows consumers to extend engine contract types', () async {
      const field = SlugField();
      const rule = AllowPublicReadRule();
      final hook = RecordingActionHook();
      const context = ActionHookContext(
        collection: 'posts',
        operation: .create,
        phase: .before,
      );

      await hook(context);

      expect(field.name, 'slug');
      expect(rule.expression, 'auth.id != ""');
      expect(hook.contexts.single, context);
    });
  });
}

class SlugField extends SchemaField {
  const SlugField() : super(name: 'slug', type: .text);
}

class AllowPublicReadRule extends AccessRule {
  const AllowPublicReadRule() : super('auth.id != ""');
}

class RecordingActionHook extends ActionHook {
  final List<ActionHookContext> contexts = <ActionHookContext>[];

  @override
  Future<void> call(ActionHookContext context) async {
    contexts.add(context);
  }
}

class MemoryStorageAdapter extends StorageAdapter {
  final List<Record> _records = <Record>[];
  final Map<String, CollectionSchema> _schemas = <String, CollectionSchema>{};

  QueryExpression? lastQuery;

  @override
  Future<CollectionSchema?> getCollectionSchema(String name) async {
    return _schemas[name];
  }

  @override
  Future<List<CollectionSchema>> listCollectionSchemas() async {
    return _schemas.values.toList();
  }

  @override
  Future<Record?> getRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    return _records
        .where((record) => record.collection == collection)
        .where((record) => record.id.value == id.value)
        .firstOrNull;
  }

  @override
  Future<RecordPage> listRecords({
    required String collection,
    QueryExpression query = const QueryExpression(),
  }) async {
    lastQuery = query;
    return RecordPage(
      items: _records
          .where((record) => record.collection == collection)
          .toList(),
      page: query.pagination.page,
      perPage: query.pagination.perPage,
      totalItems: _records.length,
    );
  }

  @override
  Future<void> putCollectionSchema(CollectionSchema schema) async {
    _schemas[schema.name] = schema;
  }

  @override
  Future<Record> putRecord(Record record) async {
    _records.add(record);
    return record;
  }

  @override
  Future<void> deleteRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    _records.removeWhere(
      (record) =>
          record.collection == collection && record.id.value == id.value,
    );
  }
}
