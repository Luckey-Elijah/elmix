import 'package:elmix_engine/src/collection_schema.dart';
import 'package:elmix_engine/src/record.dart';

/// Persistence contract implemented by storage adapter packages.
abstract class StorageAdapter {
  /// Stores [schema], replacing any existing stored schema with the same name.
  Future<void> putCollectionSchema(CollectionSchema schema);

  /// Finds a persisted collection schema by [name].
  Future<CollectionSchema?> getCollectionSchema(String name);

  /// Lists all persisted collection schemas.
  Future<List<CollectionSchema>> listCollectionSchemas();

  /// Stores [record], replacing any existing stored record with the same id.
  Future<void> putRecord(Record record);

  /// Finds a record by [collection] and [id].
  Future<Record?> getRecord(String collection, String id);

  /// Lists records stored in [collection].
  Future<List<Record>> listRecords(String collection);

  /// Deletes a record by [collection] and [id].
  Future<void> deleteRecord(String collection, String id);
}
