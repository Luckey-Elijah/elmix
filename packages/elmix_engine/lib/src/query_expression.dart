/// Supported comparison operators for field-level query filters.
enum QueryOperator {
  /// Field value equals the query value.
  equals,

  /// Field value does not equal the query value.
  notEquals,

  /// Field value is greater than the query value.
  greaterThan,

  /// Field value is greater than or equal to the query value.
  greaterThanOrEquals,

  /// Field value is less than the query value.
  lessThan,

  /// Field value is less than or equal to the query value.
  lessThanOrEquals,
}

/// Sort direction for a query result.
enum SortDirection {
  /// Ascending order.
  ascending,

  /// Descending order.
  descending,
}

/// Field comparison used in a [QueryExpression].
class QueryFilter {
  /// Creates a field comparison filter.
  const QueryFilter({
    required this.field,
    required this.operator,
    required this.value,
  });

  /// The schema field to compare.
  final String field;

  /// The comparison operator.
  final QueryOperator operator;

  /// The value to compare against.
  final Object? value;
}

/// Sorting instruction used in a [QueryExpression].
class QuerySort {
  /// Creates a field sort instruction.
  const QuerySort({
    required this.field,
    this.direction = SortDirection.ascending,
  });

  /// The schema field to sort by.
  final String field;

  /// The sort direction.
  final SortDirection direction;
}

/// Pagination instruction used in a [QueryExpression].
class QueryPagination {
  /// Creates a pagination instruction.
  const QueryPagination({
    this.page = 1,
    this.perPage = 30,
  });

  /// The one-based page number.
  final int page;

  /// The requested number of items per page.
  final int perPage;
}

/// User-supplied criteria for listing records.
class QueryExpression {
  /// Creates query criteria for listing records.
  const QueryExpression({
    this.filters = const <QueryFilter>[],
    this.sort = const <QuerySort>[],
    this.pagination = const QueryPagination(),
  });

  /// Field comparisons to apply to the target collection.
  final List<QueryFilter> filters;

  /// Sort instructions for the target collection.
  final List<QuerySort> sort;

  /// Pagination instructions for the result.
  final QueryPagination pagination;
}

/// Thrown when query criteria are outside the Engine query contract.
class QueryExpressionException implements Exception {
  /// Creates a query contract failure with a human-readable [message].
  const QueryExpressionException(this.message);

  /// Describes why the query expression is unsupported.
  final String message;

  @override
  String toString() => 'QueryExpressionException: $message';
}
