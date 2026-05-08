/// A stored item in a collection.
class Record {
  /// Creates a stored record.
  const Record({
    required this.collection,
    required this.id,
    required this.data,
  });

  /// The collection that owns this record.
  final String collection;

  /// The record identifier.
  final String id;

  /// The record payload.
  final Map<String, Object?> data;
}
