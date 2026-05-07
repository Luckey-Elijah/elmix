/// A collection operation that can be authorized by an [AccessRule].
enum CollectionOperation { list, view, create, update, delete }

/// A persisted authorization expression attached to a collection operation.
///
/// Core v0 keeps the expression as data. Parsing and evaluation can evolve
/// behind this value without changing storage or admin APIs.
class AccessRule {
  const AccessRule(this.expression);

  final String expression;
}
