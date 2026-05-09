import 'package:elmix_engine/src/collection_schema.dart';
import 'package:elmix_engine/src/query_expression.dart';
import 'package:elmix_engine/src/record.dart';

/// Persistence contract implemented by storage adapter packages.
abstract class StorageAdapter {
  /// Stores [schema], replacing any existing stored schema with the same name.
  Future<void> putCollectionSchema(CollectionSchema schema);

  /// Loads a collection schema by [name].
  Future<CollectionSchema?> getCollectionSchema(String name);

  /// Lists all persisted collection schemas.
  Future<List<CollectionSchema>> listCollectionSchemas();

  /// Stores [record], replacing any existing stored record with the same id.
  ///
  /// Adapters may assign an identifier when [record] has a blank id, and should
  /// return the stored representation.
  Future<Record> putRecord(Record record);

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

  /// Deletes one record by collection and [id].
  Future<void> deleteRecord({
    required String collection,
    required RecordIdentifier id,
  });
}
