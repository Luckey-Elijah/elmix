import 'dart:convert';

import 'package:elmix_engine/elmix_engine.dart';
import 'package:sqlite3/sqlite3.dart';

/// SQLite-backed storage adapter for Elmix.
class SqliteStorageAdapter implements StorageAdapter {
  /// Creates an in-memory SQLite storage adapter.
  SqliteStorageAdapter() : this._(sqlite3.openInMemory());

  /// Opens a file-backed SQLite storage adapter at [path].
  SqliteStorageAdapter.open(String path) : this._(sqlite3.open(path));

  SqliteStorageAdapter._(this._database) {
    _initializeMetadata();
  }

  final Database _database;

  /// Closes the underlying SQLite connection.
  void close() {
    _database.close();
  }

  @override
  Future<void> putCollectionSchema(CollectionSchema schema) async {
    final previousSchema = await getCollectionSchema(schema.name);
    _runInTransaction(() {
      _applySchema(schema, previousSchema: previousSchema);
      final statement = _database.prepare(
        '''
        INSERT INTO _elmix_collection_schemas (name, schema_json)
        VALUES (?, ?)
        ON CONFLICT(name) DO UPDATE SET schema_json = excluded.schema_json
        ''',
      );
      try {
        statement.execute(<Object?>[
          schema.name,
          jsonEncode(_schemaToJson(schema)),
        ]);
      } finally {
        statement.close();
      }
    });
  }

  @override
  Future<CollectionSchema?> getCollectionSchema(String name) async {
    final rows = _database.select(
      '''
      SELECT schema_json FROM _elmix_collection_schemas WHERE name = ?
      ''',
      <Object?>[name],
    );
    if (rows.isEmpty) {
      return null;
    }

    return _schemaFromJson(
      jsonDecode(rows.first['schema_json'] as String) as Map<String, Object?>,
    );
  }

  @override
  Future<List<CollectionSchema>> listCollectionSchemas() async {
    final rows = _database.select(
      '''
      SELECT schema_json FROM _elmix_collection_schemas ORDER BY name
      ''',
    );
    return rows
        .map((row) => row['schema_json'])
        .cast<String>()
        .map(jsonDecode)
        .cast<Map<String, Object?>>()
        .map(_schemaFromJson)
        .toList();
  }

  @override
  Future<Record> putRecord(Record record) async {
    final schema = await getCollectionSchema(record.collection);
    if (schema == null) {
      throw StateError(
        'Collection "${record.collection}" does not have an applied schema.',
      );
    }
    final stored = record.id.value.trim().isEmpty
        ? Record(
            collection: record.collection,
            id: RecordIdentifier(_nextRecordIdentifier(record.collection)),
            data: record.data,
          )
        : record;

    _runInTransaction(() {
      _applySchema(schema);
      _putSchemaRecord(stored, schema);
    });

    return stored;
  }

  @override
  Future<Record?> getRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    final schema = await getCollectionSchema(collection);
    final table = _collectionTableName(collection);
    if (!_tableExists(table)) {
      return null;
    }

    final rows = _database.select(
      '''
      SELECT * FROM ${_quoteIdentifier(table)} WHERE id = ?
      ''',
      <Object?>[id.value],
    );
    if (rows.isEmpty) {
      return null;
    }

    return _recordFromRow(
      collection: collection,
      row: rows.first,
      schema: schema,
    );
  }

  @override
  Future<RecordPage> listRecords({
    required String collection,
    QueryExpression query = const QueryExpression(),
  }) async {
    final schema = await getCollectionSchema(collection);
    final table = _collectionTableName(collection);
    if (!_tableExists(table)) {
      return RecordPage(
        items: const <Record>[],
        page: query.pagination.page,
        perPage: query.pagination.perPage,
        totalItems: 0,
      );
    }

    final rows = _database.select(
      '''
      SELECT * FROM ${_quoteIdentifier(table)}
      ''',
    );
    final records =
        rows
            .map(
              (row) => _recordFromRow(
                collection: collection,
                row: row,
                schema: schema,
              ),
            )
            .where((record) => _matchesFilters(record, query.filters))
            .toList()
          ..sort((left, right) => _compareRecords(left, right, query.sort));
    final start = (query.pagination.page - 1) * query.pagination.perPage;
    final pageItems = records
        .skip(start)
        .take(query.pagination.perPage)
        .toList();

    return RecordPage(
      items: List.unmodifiable(pageItems),
      page: query.pagination.page,
      perPage: query.pagination.perPage,
      totalItems: records.length,
    );
  }

  @override
  Future<void> deleteRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    final table = _collectionTableName(collection);
    if (!_tableExists(table)) {
      return;
    }

    final statement = _database.prepare(
      '''
      DELETE FROM ${_quoteIdentifier(table)} WHERE id = ?
      ''',
    );
    try {
      statement.execute(<Object?>[id.value]);
    } finally {
      statement.close();
    }
  }

  void _initializeMetadata() {
    _database.execute(
      '''
      CREATE TABLE IF NOT EXISTS _elmix_collection_schemas (
        name TEXT PRIMARY KEY,
        schema_json TEXT NOT NULL
      )
      ''',
    );
  }

  void _applySchema(
    CollectionSchema schema, {
    CollectionSchema? previousSchema,
  }) {
    final table = _collectionTableName(schema.name);
    _database.execute(
      '''
      CREATE TABLE IF NOT EXISTS ${_quoteIdentifier(table)} (
        id TEXT PRIMARY KEY
      )
      ''',
    );

    final existingColumns = _columnNames(table);
    if (previousSchema != null) {
      _clearRemovedFieldColumns(
        table: table,
        previousSchema: previousSchema,
        schema: schema,
        existingColumns: existingColumns,
      );
    }

    for (final field in schema.fields) {
      if (field.systemRole == FieldSystemRole.recordIdentifier) {
        continue;
      }
      if (existingColumns.contains(field.name)) {
        continue;
      }

      _database.execute(
        '''
        ALTER TABLE ${_quoteIdentifier(table)}
        ADD COLUMN ${_quoteIdentifier(field.name)} ${_sqliteType(field)}
        ''',
      );
    }
  }

  void _clearRemovedFieldColumns({
    required String table,
    required CollectionSchema previousSchema,
    required CollectionSchema schema,
    required Set<String> existingColumns,
  }) {
    final currentFieldNames = schema.fields
        .where((field) => field.systemRole != FieldSystemRole.recordIdentifier)
        .map((field) => field.name)
        .toSet();
    final removedFields = previousSchema.fields
        .where((field) => field.systemRole != FieldSystemRole.recordIdentifier)
        .where((field) => !currentFieldNames.contains(field.name))
        .where((field) => existingColumns.contains(field.name));

    for (final field in removedFields) {
      _database.execute(
        '''
        UPDATE ${_quoteIdentifier(table)}
        SET ${_quoteIdentifier(field.name)} = NULL
        ''',
      );
    }
  }

  void _putSchemaRecord(Record record, CollectionSchema schema) {
    final table = _collectionTableName(record.collection);
    final dataFields = schema.fields
        .where((field) => field.systemRole != FieldSystemRole.recordIdentifier)
        .toList();
    final columns = <String>['id', ...dataFields.map((field) => field.name)];
    final placeholders = List.filled(columns.length, '?').join(', ');
    final conflictResolution = dataFields.isEmpty
        ? 'DO NOTHING'
        : 'DO UPDATE SET ${dataFields.map(_excludedColumnUpdate).join(', ')}';
    final statement = _database.prepare(
      '''
      INSERT INTO ${_quoteIdentifier(table)}
        (${columns.map(_quoteIdentifier).join(', ')})
      VALUES ($placeholders)
      ON CONFLICT(id) $conflictResolution
      ''',
    );
    try {
      statement.execute(<Object?>[
        record.id.value,
        ...dataFields.map(
          (field) => _toSqliteValue(field, record.data[field.name]),
        ),
      ]);
    } finally {
      statement.close();
    }
  }

  Record _recordFromRow({
    required String collection,
    required Row row,
    required CollectionSchema? schema,
  }) {
    if (schema == null) {
      throw StateError(
        'Collection "$collection" does not have an applied schema.',
      );
    }

    final data = <String, Object?>{};
    for (final field in schema.fields) {
      if (field.systemRole == FieldSystemRole.recordIdentifier) {
        continue;
      }
      data[field.name] = _fromSqliteValue(field, row[field.name]);
    }

    return Record(
      collection: collection,
      id: RecordIdentifier(row['id'] as String),
      data: data,
    );
  }

  String _nextRecordIdentifier(String collection) {
    final table = _collectionTableName(collection);
    if (!_tableExists(table)) {
      return '${collection}_1';
    }

    var next =
        (_database.select(
              '''
          SELECT COUNT(*) AS record_count FROM ${_quoteIdentifier(table)}
          ''',
            ).first['record_count']
            as int) +
        1;
    while (_database
        .select(
          '''
      SELECT id FROM ${_quoteIdentifier(table)} WHERE id = ?
      ''',
          <Object?>['${collection}_$next'],
        )
        .isNotEmpty) {
      next += 1;
    }

    return '${collection}_$next';
  }

  bool _tableExists(String table) {
    return _database
        .select(
          '''
      SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?
      ''',
          <Object?>[table],
        )
        .isNotEmpty;
  }

  Set<String> _columnNames(String table) {
    return _database
        .select('PRAGMA table_info(${_quoteIdentifier(table)})')
        .map((row) => row['name'] as String)
        .toSet();
  }

  void _runInTransaction(void Function() run) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      run();
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  static String _collectionTableName(String collection) {
    return 'elmix_collection_$collection';
  }

  static String _quoteIdentifier(String identifier) {
    return '"${identifier.replaceAll('"', '""')}"';
  }

  static String _excludedColumnUpdate(SchemaField field) {
    final column = _quoteIdentifier(field.name);
    return '$column = excluded.$column';
  }

  static String _sqliteType(SchemaField field) {
    return switch (field.type) {
      FieldType.number => 'REAL',
      FieldType.bool => 'INTEGER',
      FieldType.text ||
      FieldType.email ||
      FieldType.password ||
      FieldType.select ||
      FieldType.relation ||
      FieldType.date ||
      FieldType.json => 'TEXT',
    };
  }

  static Object? _toSqliteValue(SchemaField field, Object? value) {
    if (value == null) {
      return null;
    }

    return switch (field.type) {
      FieldType.bool => (value as bool) ? 1 : 0,
      FieldType.date => (value as DateTime).toIso8601String(),
      FieldType.json => jsonEncode(value),
      _ => value,
    };
  }

  static Object? _fromSqliteValue(SchemaField field, Object? value) {
    if (value == null) {
      return null;
    }

    return switch (field.type) {
      FieldType.bool => value == 1,
      FieldType.date => DateTime.parse(value as String),
      FieldType.json => jsonDecode(value as String),
      FieldType.number => value,
      _ => value,
    };
  }

  static Map<String, Object?> _schemaToJson(CollectionSchema schema) {
    return <String, Object?>{
      'name': schema.name,
      'isAuthCollection': schema.isAuthCollection,
      'fields': schema.fields.map(_fieldToJson).toList(),
      'accessRules': schema.accessRules.map(
        (operation, rule) => MapEntry(operation.name, rule.expression),
      ),
    };
  }

  static Map<String, Object?> _fieldToJson(SchemaField field) {
    return <String, Object?>{
      'name': field.name,
      'type': field.type.name,
      'required': field.required,
      'removable': field.removable,
      'systemRole': field.systemRole.name,
      'targetCollection': field.targetCollection,
    };
  }

  static CollectionSchema _schemaFromJson(Map<String, Object?> json) {
    final fieldsJson = json['fields']! as List<Object?>;
    final rulesJson = json['accessRules']! as Map<String, Object?>;
    final fields = fieldsJson
        .cast<Map<String, Object?>>()
        .map(_fieldFromJson)
        .toList();
    final accessRules = rulesJson.map(
      (operation, expression) => MapEntry(
        CollectionOperation.values.byName(operation),
        AccessRule(expression! as String),
      ),
    );

    if (json['isAuthCollection']! as bool) {
      return CollectionSchema.auth(
        name: json['name']! as String,
        fields: fields,
        accessRules: accessRules,
      );
    }

    return CollectionSchema(
      name: json['name']! as String,
      fields: fields,
      accessRules: accessRules,
    );
  }

  static SchemaField _fieldFromJson(Map<String, Object?> json) {
    return SchemaField(
      name: json['name']! as String,
      type: FieldType.values.byName(json['type']! as String),
      required: json['required']! as bool,
      removable: json['removable']! as bool,
      systemRole: FieldSystemRole.values.byName(json['systemRole']! as String),
      targetCollection: json['targetCollection'] as String?,
    );
  }

  static bool _matchesFilters(Record record, List<QueryFilter> filters) {
    return filters.every((filter) {
      final value = _fieldValue(record, filter.field);

      return switch (filter.operator) {
        QueryOperator.equals => value == filter.value,
        QueryOperator.notEquals => value != filter.value,
        QueryOperator.greaterThan => _matchesRange(
          value,
          filter.value,
          (comparison) => comparison > 0,
        ),
        QueryOperator.greaterThanOrEquals => _matchesRange(
          value,
          filter.value,
          (comparison) => comparison >= 0,
        ),
        QueryOperator.lessThan => _matchesRange(
          value,
          filter.value,
          (comparison) => comparison < 0,
        ),
        QueryOperator.lessThanOrEquals => _matchesRange(
          value,
          filter.value,
          (comparison) => comparison <= 0,
        ),
      };
    });
  }

  static int _compareRecords(
    Record left,
    Record right,
    List<QuerySort> sort,
  ) {
    for (final instruction in sort) {
      final direction = instruction.direction == SortDirection.ascending
          ? 1
          : -1;
      final comparison =
          _compareValues(
            _fieldValue(left, instruction.field),
            _fieldValue(right, instruction.field),
          ) *
          direction;

      if (comparison != 0) {
        return comparison;
      }
    }

    return 0;
  }

  static Object? _fieldValue(Record record, String field) {
    if (field == 'id') {
      return record.id.value;
    }

    return record.data[field];
  }

  static bool _matchesRange(
    Object? left,
    Object? right,
    bool Function(int comparison) predicate,
  ) {
    if (left == null || right == null) {
      return false;
    }

    return predicate(_compareValues(left, right));
  }

  static int _compareValues(Object? left, Object? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    if (left is num && right is num) {
      return left.compareTo(right);
    }
    if (left is DateTime && right is DateTime) {
      return left.compareTo(right);
    }
    if (left is String && right is String) {
      return left.compareTo(right);
    }
    if (left is bool && right is bool) {
      return left == right ? 0 : (left ? 1 : -1);
    }

    return left.toString().compareTo(right.toString());
  }
}
