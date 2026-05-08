import 'package:elmix_engine/src/collection_schema.dart';
import 'package:elmix_engine/src/query_expression.dart';
import 'package:elmix_engine/src/record.dart';

/// Persistence contract implemented by storage adapter packages.
abstract class StorageAdapter {
  /// Persists or replaces [schema].
  Future<void> saveCollectionSchema(CollectionSchema schema);

  /// Lists all persisted collection schemas.
  Future<List<CollectionSchema>> listCollectionSchemas();

  /// Loads a collection schema by [name].
  Future<CollectionSchema?> getCollectionSchema(String name);

  /// Persists or replaces [record].
  Future<void> saveRecord(Record record);

  /// Loads one record by collection and [id].
  Future<Record?> getRecord({
    required String collection,
    required RecordIdentifier id,
  });

  /// Lists records stored in [collection].
  Future<RecordPage> listRecords({
    required String collection,
    QueryExpression query = const QueryExpression(),
  });
}
