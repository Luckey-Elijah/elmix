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

/// Thrown when record data does not satisfy its collection schema.
class RecordValidationException implements Exception {
  /// Creates a validation failure with a human-readable [message].
  const RecordValidationException(this.message);

  /// Describes why validation failed.
  final String message;

  @override
  String toString() => 'RecordValidationException: $message';
}

/// Thrown when record operations are used through the wrong collection handle.
class RecordCollectionMismatchException extends RecordValidationException {
  /// Creates a collection mismatch validation failure.
  const RecordCollectionMismatchException({
    required String expectedCollection,
    required String actualCollection,
  }) : super(
         'Expected record for collection "$expectedCollection", '
         'but received "$actualCollection".',
       );
}
