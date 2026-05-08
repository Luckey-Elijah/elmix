/// A collection operation that can be authorized by an [AccessRule].
enum CollectionOperation {
  /// Lists records in a collection.
  list,

  /// Views a single record in a collection.
  view,

  /// Creates a record in a collection.
  create,

  /// Updates a record in a collection.
  update,

  /// Deletes a record from a collection.
  delete,
}

/// A persisted authorization expression attached to a collection operation.
///
/// Core v0 keeps the expression as data. Parsing and evaluation can evolve
/// behind this value without changing storage or admin APIs.
class AccessRule {
  /// Creates an access rule from a persisted [expression].
  const AccessRule(this.expression);

  /// The persisted authorization expression.
  final String expression;
}
