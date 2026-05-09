import 'package:elmix_engine/src/action_hook.dart';
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
  ElmixEngine({required StorageAdapter storage}) : _storage = storage;

  final StorageAdapter _storage;
  final List<ActionHook> _hooks = [];

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

  /// Opens the record API for the collection named [name].
  CollectionHandle collection(String name) {
    return CollectionHandle(name: name, storage: _storage);
  }

  /// Adds a lifecycle [hook] to the engine.
  void addHook(ActionHook hook) {
    _hooks.add(hook);
  }

  /// The registered lifecycle hooks.
  List<ActionHook> get hooks => List.unmodifiable(_hooks);
}

/// Record use cases scoped to one collection.
class CollectionHandle {
  /// Creates a collection-scoped record API backed by [storage].
  CollectionHandle({
    required this.name,
    required StorageAdapter storage,
  }) : _storage = storage;

  /// The collection name this handle operates on.
  final String name;

  final StorageAdapter _storage;

  /// Creates [record] in this collection.
  Future<Record> create(Record record) async {
    await _validateRecord(record, requireIdentifier: false);
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

    return _storage.putRecord(record);
  }

  /// Saves [record] to this collection.
  Future<Record> save(Record record) async {
    await _validateRecord(record, requireIdentifier: false);
    return _storage.putRecord(record);
  }

  /// Gets a record by exact [id].
  Future<Record?> get(RecordIdentifier id) {
    return _storage.getRecord(collection: name, id: id);
  }

  /// Updates [record] in this collection.
  Future<Record> update(Record record) async {
    await _validateRecord(record);
    return _storage.putRecord(record);
  }

  /// Lists records in this collection.
  Future<RecordPage> list({
    QueryExpression query = const QueryExpression(),
  }) {
    return _storage.listRecords(collection: name, query: query);
  }

  /// Deletes a record by exact [id].
  Future<void> delete(RecordIdentifier id) {
    return _storage.deleteRecord(collection: name, id: id);
  }

  Future<void> _validateRecord(
    Record record, {
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

    final schema = await _storage.getCollectionSchema(name);
    if (schema == null) {
      throw RecordValidationException(
        'Collection "$name" is not registered.',
      );
    }

    final dataFields = schema.fields
        .where((field) => field.systemRole != FieldSystemRole.recordIdentifier)
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
      if (field.systemRole == FieldSystemRole.recordIdentifier) {
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
