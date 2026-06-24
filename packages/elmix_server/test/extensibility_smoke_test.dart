import 'package:elmix_engine/elmix_engine.dart';
import 'package:elmix_server/elmix_server.dart';
import 'package:test/test.dart';

void main() {
  test('a consumer can extend the server boundary', () {
    final server = ConsumerServer(
      ElmixEngine(storage: ConsumerStorageAdapter()),
    );

    expect(server, isA<ElmixServer>());
    expect(server.productName, 'consumer app');
  });
}

class ConsumerServer extends ElmixServer {
  ConsumerServer(super.engine);

  String get productName => 'consumer app';
}

class ConsumerStorageAdapter implements StorageAdapter {
  @override
  Future<void> deleteCollectionSchema(String name) =>
      throw UnimplementedError();

  @override
  Future<void> deleteRecord({
    required String collection,
    required RecordIdentifier id,
  }) => throw UnimplementedError();

  @override
  Future<CollectionSchema?> getCollectionSchema(String name) =>
      throw UnimplementedError();

  @override
  Future<Record?> getRecord({
    required String collection,
    required RecordIdentifier id,
  }) => throw UnimplementedError();

  @override
  Future<List<CollectionSchema>> listCollectionSchemas() =>
      throw UnimplementedError();

  @override
  Future<RecordPage> listRecords({
    required String collection,
    QueryExpression query = const QueryExpression(),
  }) => throw UnimplementedError();

  @override
  Future<void> putCollectionSchema(CollectionSchema schema) =>
      throw UnimplementedError();

  @override
  Future<Record> putRecord(Record record) => throw UnimplementedError();
}
