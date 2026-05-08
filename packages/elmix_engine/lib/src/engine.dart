import 'package:elmix_engine/src/action_hook.dart';
import 'package:elmix_engine/src/collection_schema.dart';
import 'package:elmix_engine/src/record.dart';
import 'package:elmix_engine/src/storage_adapter.dart';

/// Core runtime facade for Elmix application semantics.
///
/// This deliberately starts tiny. The engine should grow use-case methods here
/// while keeping HTTP, SQLite, admin UI, and CLI details outside the package.
class ElmixEngine {
  /// Creates an engine backed by [storage].
  ElmixEngine({required StorageAdapter storage}) : _storage = storage;

  final StorageAdapter _storage;
  final List<ActionHook> _hooks = [];

  /// Registers or replaces a collection schema.
  Future<void> registerCollection(CollectionSchema schema) {
    return _storage.saveCollectionSchema(schema);
  }

  /// Lists all registered collection schemas.
  Future<List<CollectionSchema>> listCollections() {
    return _storage.listCollectionSchemas();
  }

  /// Saves [record] to its collection.
  Future<void> saveRecord(Record record) {
    return _storage.saveRecord(record);
  }

  /// Lists records from [collection].
  Future<List<Record>> listRecords(String collection) {
    return _storage.listRecords(collection);
  }

  /// Adds a lifecycle [hook] to the engine.
  void addHook(ActionHook hook) {
    _hooks.add(hook);
  }

  /// The registered lifecycle hooks.
  List<ActionHook> get hooks => List.unmodifiable(_hooks);
}
