import 'package:elmix_engine/src/access_rule.dart';
import 'package:elmix_engine/src/action_hook.dart';
import 'package:elmix_engine/src/auth.dart';
import 'package:elmix_engine/src/collection_schema.dart';
import 'package:elmix_engine/src/query_expression.dart';
import 'package:elmix_engine/src/record.dart';
import 'package:elmix_engine/src/storage_adapter.dart';

/// Core runtime facade for Elmix application semantics.
///
/// This deliberately starts tiny. The engine should grow use-case methods here
/// while keeping HTTP, SQLite, admin UI, and CLI details outside the package.
class ElmixEngine {
  /// Creates an engine backed by [storage].
  ElmixEngine({
    required StorageAdapter storage,
    this.credentialHasher = const Pbkdf2CredentialHasher(),
  }) : _storage = storage;

  final StorageAdapter _storage;

  /// Credential hasher used for password fields and Auth Record login.
  final CredentialHasher credentialHasher;
  final List<ActionHook> _hooks = [];
  final List<AuthenticationActionHook> _authenticationHooks = [];

  /// Registers a new collection schema.
  Future<void> registerCollection(CollectionSchema schema) async {
    final existing = await _storage.getCollectionSchema(schema.name);
    if (existing != null) {
      throw CollectionSchemaException(
        'Collection "${schema.name}" is already registered.',
      );
    }

    return _storage.putCollectionSchema(schema);
  }

  /// Replaces an existing collection schema.
  Future<void> updateCollectionSchema(CollectionSchema schema) async {
    final existing = await _storage.getCollectionSchema(schema.name);
    if (existing == null) {
      throw CollectionSchemaException(
        'Collection "${schema.name}" is not registered.',
      );
    }

    return _storage.putCollectionSchema(schema);
  }

  /// Gets a registered collection schema by exact [name].
  Future<CollectionSchema?> getCollectionSchema(String name) {
    return _storage.getCollectionSchema(name);
  }

  /// Lists all registered collection schemas.
  Future<List<CollectionSchema>> listCollections() {
    return _storage.listCollectionSchemas();
  }

  /// Deletes a registered collection schema and its records.
  Future<void> deleteCollectionSchema(String name) async {
    final existing = await _storage.getCollectionSchema(name);
    if (existing == null) {
      throw CollectionSchemaException(
        'Collection "$name" is not registered.',
      );
    }

    return _storage.deleteCollectionSchema(name);
  }

  /// Opens the record API for the collection named [name].
  CollectionHandle collection(
    String name, {
    RequestContext context = RequestContext.anonymous,
  }) {
    return CollectionHandle(
      name: name,
      storage: _storage,
      context: context,
      hooks: _hooks,
      credentialHasher: credentialHasher,
    );
  }

  /// Adds a lifecycle [hook] to the engine.
  void addHook(ActionHook hook) {
    _hooks.add(hook);
  }

  /// The registered lifecycle hooks.
  List<ActionHook> get hooks => List.unmodifiable(_hooks);

  /// Adds a lifecycle [hook] for authentication actions.
  void addAuthenticationHook(AuthenticationActionHook hook) {
    _authenticationHooks.add(hook);
  }

  /// Authenticates an Auth Record by email and password.
  Future<AuthRecord> authenticateAuthRecordWithPassword({
    required String collection,
    required String email,
    required String password,
  }) async {
    final schema = await _storage.getCollectionSchema(collection);
    if (schema == null || !schema.isAuthCollection) {
      throw CollectionSchemaException(
        'Collection "$collection" is not an Auth Collection.',
      );
    }

    final page = await _storage.listRecords(
      collection: collection,
      query: QueryExpression(
        filters: <QueryFilter>[
          QueryFilter(
            field: 'email',
            operator: QueryOperator.equals,
            value: email,
          ),
        ],
        pagination: const QueryPagination(perPage: 1000),
      ),
    );
    final matching = page.items.where(
      (record) => credentialHasher.verify(
        password: password,
        stored: record.data['password'],
      ),
    );
    if (matching.isEmpty) {
      throw const AuthRecordAuthenticationException(
        'Auth Record credentials are invalid.',
      );
    }

    final record = matching.first;
    final identity = await runAuthenticationAction(
      collection: collection,
      action: AuthenticationOperation.authenticate,
      run: () async => AuthRecordIdentity(
        collection: collection,
        id: record.id,
      ),
    );
    return AuthRecord(
      collection: identity.collection,
      id: identity.id,
      data: record.data,
    );
  }

  /// Runs an authentication [action] with before and after lifecycle hooks.
  Future<AuthRecordIdentity> runAuthenticationAction({
    required String collection,
    required AuthenticationOperation action,
    required Future<AuthRecordIdentity> Function() run,
  }) async {
    await _runAuthenticationHooks(
      collection: collection,
      action: action,
      phase: .before,
    );
    final authRecord = await run();
    await _runAuthenticationHooks(
      collection: collection,
      action: action,
      phase: .after,
      authRecord: authRecord,
    );
    return authRecord;
  }

  Future<void> _runAuthenticationHooks({
    required String collection,
    required AuthenticationOperation action,
    required HookPhase phase,
    AuthRecordIdentity? authRecord,
  }) async {
    final context = AuthenticationActionHookContext(
      collection: collection,
      action: action,
      phase: phase,
      authRecord: authRecord,
    );
    for (final hook in _authenticationHooks) {
      await hook(context);
    }
  }
}

/// Record use cases scoped to one collection.
class CollectionHandle {
  /// Creates a collection-scoped record API backed by [storage].
  CollectionHandle({
    required this.name,
    required StorageAdapter storage,
    RequestContext context = RequestContext.anonymous,
    List<ActionHook> hooks = const <ActionHook>[],
    CredentialHasher credentialHasher = const Pbkdf2CredentialHasher(),
  }) : _storage = storage,
       _context = context,
       _hooks = hooks,
       _credentialHasher = credentialHasher;

  /// The collection name this handle operates on.
  final String name;

  final StorageAdapter _storage;
  final RequestContext _context;
  final List<ActionHook> _hooks;
  final CredentialHasher _credentialHasher;

  /// Creates [record] in this collection.
  Future<Record> create(Record record) async {
    final schema = await _requireSchema();
    _authorize(
      schema: schema,
      operation: .create,
      requestRecord: record,
    );
    await _runHooks(
      operation: .create,
      phase: .before,
      record: record,
    );
    await _validateRecord(record, schema: schema, requireIdentifier: false);
    final recordToStore = _recordWithHashedPasswords(record, schema: schema);
    if (record.id.value.trim().isNotEmpty) {
      final existing = await _storage.getRecord(
        collection: name,
        id: record.id,
      );
      if (existing != null) {
        throw RecordValidationException(
          'Record "${record.id.value}" already exists in collection "$name".',
        );
      }
    }

    final created = await _storage.putRecord(recordToStore);
    await _runHooks(
      operation: .create,
      phase: .after,
      record: created,
    );
    return created;
  }

  /// Saves [record] to this collection.
  Future<Record> save(Record record) async {
    final schema = await _requireSchema();
    await _validateRecord(record, schema: schema, requireIdentifier: false);
    final existing = record.id.value.trim().isEmpty
        ? null
        : await _storage.getRecord(collection: name, id: record.id);
    final operation = existing == null
        ? CollectionOperation.create
        : CollectionOperation.update;
    _authorize(
      schema: schema,
      operation: operation,
      record: existing,
      requestRecord: record,
    );
    await _runHooks(
      operation: operation,
      phase: .before,
      record: record,
    );
    final saved = await _storage.putRecord(
      _recordWithHashedPasswords(record, schema: schema),
    );
    await _runHooks(
      operation: operation,
      phase: .after,
      record: saved,
    );
    return saved;
  }

  /// Gets a record by exact [id].
  Future<Record?> get(RecordIdentifier id) async {
    final schema = await _requireSchema();
    final record = await _storage.getRecord(collection: name, id: id);
    _authorize(
      schema: schema,
      operation: .view,
      record: record,
    );
    await _runHooks(
      operation: .view,
      phase: .before,
      record: record,
    );
    await _runHooks(
      operation: .view,
      phase: .after,
      record: record,
    );
    return record;
  }

  /// Updates [record] in this collection.
  Future<Record> update(Record record) async {
    final schema = await _requireSchema();
    await _validateRecord(record, schema: schema);
    final existing = await _storage.getRecord(collection: name, id: record.id);
    if (existing == null) {
      throw RecordValidationException(
        'Record "${record.id.value}" does not exist in collection "$name".',
      );
    }

    _authorize(
      schema: schema,
      operation: .update,
      record: existing,
      requestRecord: record,
    );
    await _runHooks(
      operation: .update,
      phase: .before,
      record: record,
    );
    final updated = await _storage.putRecord(
      _recordWithHashedPasswords(record, schema: schema),
    );
    await _runHooks(
      operation: .update,
      phase: .after,
      record: updated,
    );
    return updated;
  }

  /// Lists records in this collection.
  Future<RecordPage> list({
    QueryExpression query = const QueryExpression(),
  }) async {
    final schema = await _requireSchema();
    _authorize(schema: schema, operation: .list);
    _validateQuery(query, schema: schema);
    await _runHooks(
      operation: .list,
      phase: .before,
    );
    final page = await _storage.listRecords(collection: name, query: query);
    await _runHooks(
      operation: .list,
      phase: .after,
    );
    return page;
  }

  /// Deletes a record by exact [id].
  Future<void> delete(RecordIdentifier id) async {
    final schema = await _requireSchema();
    final record = await _storage.getRecord(collection: name, id: id);
    _authorize(
      schema: schema,
      operation: .delete,
      record: record,
    );
    await _runHooks(
      operation: .delete,
      phase: .before,
      record: record,
    );
    await _storage.deleteRecord(collection: name, id: id);
    await _runHooks(
      operation: .delete,
      phase: .after,
      record: record,
    );
  }

  Future<void> _runHooks({
    required CollectionOperation operation,
    required HookPhase phase,
    Record? record,
  }) async {
    final context = ActionHookContext(
      collection: name,
      operation: operation,
      phase: phase,
      record: record,
      authRecord: _context.authRecord,
    );
    for (final hook in _hooks) {
      await hook(context);
    }
  }

  void _validateQuery(
    QueryExpression query, {
    required CollectionSchema schema,
  }) {
    if (query.pagination.page < 1) {
      throw const QueryExpressionException('Query page must be at least 1.');
    }
    if (query.pagination.perPage < 1) {
      throw const QueryExpressionException('Query perPage must be at least 1.');
    }

    final fieldNames = {
      'id',
      ...schema.fields.map((field) => field.name),
    };
    final queriedFields = [
      ...query.filters.map((filter) => filter.field),
      ...query.sort.map((sort) => sort.field),
    ];
    for (final field in queriedFields) {
      if (field.contains('.')) {
        throw QueryExpressionException(
          'Query field "$field" is outside the Engine query contract.',
        );
      }
      if (!fieldNames.contains(field)) {
        throw QueryExpressionException(
          'Query field "$field" is not declared by collection "$name".',
        );
      }
    }
  }

  Future<CollectionSchema> _requireSchema() async {
    final schema = await _storage.getCollectionSchema(name);
    if (schema == null) {
      throw RecordValidationException(
        'Collection "$name" is not registered.',
      );
    }
    return schema;
  }

  void _authorize({
    required CollectionSchema schema,
    required CollectionOperation operation,
    Record? record,
    Record? requestRecord,
  }) {
    if (_context.isSystem) {
      return;
    }

    final rule = schema.accessRules[operation];
    if (rule == null || rule.expression.trim().isEmpty) {
      return;
    }

    if (!_AccessRuleEvaluator(
      context: _context,
      record: record,
      requestRecord: requestRecord,
    ).allows(rule)) {
      throw AuthorizationException(
        'Collection "$name" ${operation.name} request is not authorized.',
      );
    }
  }

  Future<void> _validateRecord(
    Record record, {
    required CollectionSchema schema,
    bool requireIdentifier = true,
  }) async {
    if (record.collection != name) {
      throw RecordCollectionMismatchException(
        expectedCollection: name,
        actualCollection: record.collection,
      );
    }

    if (requireIdentifier && record.id.value.trim().isEmpty) {
      throw const RecordValidationException('Record id is required.');
    }

    final dataFields = schema.fields
        .where((field) => field.systemRole != .recordIdentifier)
        .toList();
    final dataFieldNames = dataFields.map((field) => field.name).toSet();

    for (final fieldName in record.data.keys) {
      if (!dataFieldNames.contains(fieldName)) {
        throw RecordValidationException(
          'Field "$fieldName" is not declared by collection "$name".',
        );
      }
    }

    for (final field in dataFields) {
      if (field.systemRole == .recordIdentifier) {
        continue;
      }

      final value = record.data[field.name];
      if (value == null) {
        if (field.required) {
          throw RecordValidationException(
            'Field "${field.name}" is required.',
          );
        }
        continue;
      }

      if (!_isValidFieldValue(field, value)) {
        throw RecordValidationException(
          'Field "${field.name}" must be ${field.type.name}.',
        );
      }
    }
  }

  Record _recordWithHashedPasswords(
    Record record, {
    required CollectionSchema schema,
  }) {
    final passwordFields = <String>{
      for (final field in schema.fields)
        if (field.type == FieldType.password) field.name,
    };
    if (passwordFields.isEmpty) {
      return record;
    }

    return Record(
      collection: record.collection,
      id: record.id,
      data: <String, Object?>{
        for (final entry in record.data.entries)
          entry.key:
              passwordFields.contains(entry.key) &&
                  !_credentialHasher.isHash(entry.value)
              ? _credentialHasher.hash(entry.value! as String)
              : entry.value,
      },
    );
  }

  bool _isValidFieldValue(SchemaField field, Object value) {
    return switch (field.type) {
      .text || .email || .password || .select || .relation => value is String,
      .number => value is num,
      .bool => value is bool,
      .date => value is DateTime,
      .json => _isJsonValue(value),
    };
  }

  bool _isJsonValue(Object? value) {
    return switch (value) {
      null || String() || num() || bool() => true,
      final List<Object?> list => list.every(_isJsonValue),
      final Map<String, Object?> map => map.values.every(_isJsonValue),
      _ => false,
    };
  }
}

class _AccessRuleEvaluator {
  _AccessRuleEvaluator({
    required RequestContext context,
    Record? record,
    Record? requestRecord,
  }) : _context = context,
       _record = record,
       _requestRecord = requestRecord;

  final RequestContext _context;
  final Record? _record;
  final Record? _requestRecord;

  bool allows(AccessRule rule) {
    final expression = rule.expression.trim();
    if (expression == 'true') {
      return true;
    }
    if (expression == 'false') {
      return false;
    }

    return expression
        .split('&&')
        .map((part) => part.trim())
        .every(_evaluateComparison);
  }

  bool _evaluateComparison(String comparison) {
    final operator = ['>=', '<=', '!=', '==', '>', '<']
        .where(
          comparison.contains,
        )
        .firstOrNull;
    if (operator == null) {
      return false;
    }

    final parts = comparison.split(operator);
    if (parts.length != 2) {
      return false;
    }

    final left = _resolve(parts[0].trim());
    final right = _resolve(parts[1].trim());
    final compared = _compare(left, right);
    return switch (operator) {
      '==' => left == right,
      '!=' => left != right,
      '>' => compared != null && compared > 0,
      '>=' => compared != null && compared >= 0,
      '<' => compared != null && compared < 0,
      '<=' => compared != null && compared <= 0,
      _ => false,
    };
  }

  Object? _resolve(String token) {
    if (token.length >= 2 && token.startsWith('"') && token.endsWith('"')) {
      return token.substring(1, token.length - 1);
    }
    if (token == 'true') {
      return true;
    }
    if (token == 'false') {
      return false;
    }
    final number = num.tryParse(token);
    if (number != null) {
      return number;
    }

    return switch (token) {
      'auth.id' => _context.authRecord?.id.value,
      'auth.collection' => _context.authRecord?.collection,
      'record.id' => _record?.id.value,
      final field when field.startsWith('record.data.') =>
        _record?.data[field.substring('record.data.'.length)],
      final field when field.startsWith('request.data.') =>
        _requestRecord?.data[field.substring('request.data.'.length)],
      _ => null,
    };
  }

  int? _compare(Object? left, Object? right) {
    return switch ((left, right)) {
      (final num left, final num right) => left.compareTo(right),
      (final String left, final String right) => left.compareTo(right),
      (final bool left, final bool right) =>
        left == right
            ? 0
            : left
            ? 1
            : -1,
      (final DateTime left, final DateTime right) => left.compareTo(right),
      _ => null,
    };
  }
}
