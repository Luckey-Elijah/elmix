/// A stored item in a collection.
final class Record {
  const Record({
    required this.collection,
    required this.id,
    required this.data,
  });

  final String collection;
  final String id;
  final Map<String, Object?> data;
}
