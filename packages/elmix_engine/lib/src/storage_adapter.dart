import 'collection_schema.dart';
import 'record.dart';

/// Persistence contract implemented by storage adapter packages.
abstract interface class StorageAdapter {
  Future<void> saveCollectionSchema(CollectionSchema schema);

  Future<List<CollectionSchema>> listCollectionSchemas();

  Future<void> saveRecord(Record record);

  Future<List<Record>> listRecords(String collection);
}
