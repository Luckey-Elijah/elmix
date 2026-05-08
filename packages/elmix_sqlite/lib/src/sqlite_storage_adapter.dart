import 'package:elmix_engine/elmix_engine.dart';

/// Placeholder SQLite adapter boundary.
///
/// Real SQLite persistence will be added once the Engine storage contract is
/// stable enough to bind to a concrete database implementation.
class SqliteStorageAdapter implements StorageAdapter {
  final List<CollectionSchema> _schemas = [];
  final Map<String, List<Record>> _records = {};

  @override
  Future<void> saveCollectionSchema(CollectionSchema schema) async {
    _schemas
      ..removeWhere((existing) => existing.name == schema.name)
      ..add(schema);
  }

  @override
  Future<List<CollectionSchema>> listCollectionSchemas() async {
    return List.unmodifiable(_schemas);
  }

  @override
  Future<CollectionSchema?> getCollectionSchema(String name) async {
    return _schemas.where((schema) => schema.name == name).firstOrNull;
  }

  @override
  Future<void> saveRecord(Record record) async {
    _records.putIfAbsent(record.collection, () => [])
      ..removeWhere((existing) => existing.id.value == record.id.value)
      ..add(record);
  }

  @override
  Future<Record?> getRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    return (_records[collection] ?? const <Record>[])
        .where((record) => record.id.value == id.value)
        .firstOrNull;
  }

  @override
  Future<RecordPage> listRecords({
    required String collection,
    QueryExpression query = const QueryExpression(),
  }) async {
    final records = _records[collection] ?? const <Record>[];
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
}
