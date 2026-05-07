import 'package:elmix_engine/elmix_engine.dart';

/// Placeholder SQLite adapter boundary.
///
/// Real SQLite persistence will be added once the Engine storage contract is
/// stable enough to bind to a concrete database implementation.
final class SqliteStorageAdapter implements StorageAdapter {
  final List<CollectionSchema> _schemas = [];
  final Map<String, List<Record>> _records = {};

  @override
  Future<void> saveCollectionSchema(CollectionSchema schema) async {
    _schemas.removeWhere((existing) => existing.name == schema.name);
    _schemas.add(schema);
  }

  @override
  Future<List<CollectionSchema>> listCollectionSchemas() async {
    return List.unmodifiable(_schemas);
  }

  @override
  Future<void> saveRecord(Record record) async {
    final records = _records.putIfAbsent(record.collection, () => []);
    records.removeWhere((existing) => existing.id == record.id);
    records.add(record);
  }

  @override
  Future<List<Record>> listRecords(String collection) async {
    return List.unmodifiable(_records[collection] ?? const []);
  }
}
