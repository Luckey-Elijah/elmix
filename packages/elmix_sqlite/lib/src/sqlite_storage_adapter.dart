import 'package:elmix_engine/elmix_engine.dart';

/// Placeholder SQLite adapter boundary.
///
/// Real SQLite persistence will be added once the Engine storage contract is
/// stable enough to bind to a concrete database implementation.
class SqliteStorageAdapter implements StorageAdapter {
  final List<CollectionSchema> _schemas = [];
  final Map<String, List<Record>> _records = {};

  @override
  Future<void> putCollectionSchema(CollectionSchema schema) async {
    _schemas
      ..removeWhere((existing) => existing.name == schema.name)
      ..add(schema);
  }

  @override
  Future<CollectionSchema?> getCollectionSchema(String name) async {
    return _schemas.where((schema) => schema.name == name).firstOrNull;
  }

  @override
  Future<List<CollectionSchema>> listCollectionSchemas() async {
    return List.unmodifiable(_schemas);
  }

  @override
  Future<void> putRecord(Record record) async {
    _records.putIfAbsent(record.collection, () => [])
      ..removeWhere((existing) => existing.id == record.id)
      ..add(record);
  }

  @override
  Future<Record?> getRecord(String collection, String id) async {
    return _records[collection]?.where((record) => record.id == id).firstOrNull;
  }

  @override
  Future<List<Record>> listRecords(String collection) async {
    return List.unmodifiable(_records[collection] ?? const []);
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    _records[collection]?.removeWhere((record) => record.id == id);
  }
}
