import 'action_hook.dart';
import 'collection_schema.dart';
import 'record.dart';
import 'storage_adapter.dart';

/// Core runtime facade for Elmix application semantics.
///
/// This deliberately starts tiny. The engine should grow use-case methods here
/// while keeping HTTP, SQLite, admin UI, and CLI details outside the package.
final class ElmixEngine {
  ElmixEngine({required StorageAdapter storage}) : _storage = storage;

  final StorageAdapter _storage;
  final List<ActionHook> _hooks = [];

  Future<void> registerCollection(CollectionSchema schema) {
    return _storage.saveCollectionSchema(schema);
  }

  Future<List<CollectionSchema>> listCollections() {
    return _storage.listCollectionSchemas();
  }

  Future<void> saveRecord(Record record) {
    return _storage.saveRecord(record);
  }

  Future<List<Record>> listRecords(String collection) {
    return _storage.listRecords(collection);
  }

  void addHook(ActionHook hook) {
    _hooks.add(hook);
  }

  List<ActionHook> get hooks => List.unmodifiable(_hooks);
}
