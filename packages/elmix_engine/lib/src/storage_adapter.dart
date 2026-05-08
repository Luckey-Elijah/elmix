import 'package:elmix_engine/src/collection_schema.dart';
import 'package:elmix_engine/src/record.dart';

/// Persistence contract implemented by storage adapter packages.
abstract class StorageAdapter {
  /// Persists or replaces [schema].
  Future<void> saveCollectionSchema(CollectionSchema schema);

  /// Lists all persisted collection schemas.
  Future<List<CollectionSchema>> listCollectionSchemas();

  /// Persists or replaces [record].
  Future<void> saveRecord(Record record);

  /// Lists records stored in [collection].
  Future<List<Record>> listRecords(String collection);
}
