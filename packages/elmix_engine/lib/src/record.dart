/// Stable identity for a record in a collection.
class RecordIdentifier {
  /// Creates a record identifier.
  const RecordIdentifier(this.value);

  /// The persisted identifier value.
  final String value;
}

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
  final RecordIdentifier id;

  /// The record payload.
  final Map<String, Object?> data;
}

/// A paginated record listing result.
class RecordPage {
  /// Creates a page of records.
  const RecordPage({
    required this.items,
    required this.page,
    required this.perPage,
    required this.totalItems,
  });

  /// Records on this page.
  final List<Record> items;

  /// The one-based page number.
  final int page;

  /// The requested number of items per page.
  final int perPage;

  /// Total records matching the query.
  final int totalItems;
}
