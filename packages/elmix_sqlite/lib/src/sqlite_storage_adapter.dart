import 'package:elmix_engine/elmix_engine.dart';

/// Placeholder SQLite adapter boundary.
///
/// Real SQLite persistence will be added once the Engine storage contract is
/// stable enough to bind to a concrete database implementation.
class SqliteStorageAdapter implements StorageAdapter {
  final List<CollectionSchema> _schemas = [];
  final Map<String, List<Record>> _records = {};

  @override
  Future<void> putCollectionSchema(CollectionSchema schema) async {
    _schemas
      ..removeWhere((existing) => existing.name == schema.name)
      ..add(schema);
  }

  @override
  Future<CollectionSchema?> getCollectionSchema(String name) async {
    return _schemas.where((schema) => schema.name == name).firstOrNull;
  }

  @override
  Future<List<CollectionSchema>> listCollectionSchemas() async {
    return List.unmodifiable(_schemas);
  }

  @override
  Future<Record> putRecord(Record record) async {
    final stored = _recordWithStorageIdentifier(record);
    _records.putIfAbsent(stored.collection, () => [])
      ..removeWhere((existing) => existing.id.value == stored.id.value)
      ..add(stored);

    return stored;
  }

  @override
  Future<Record?> getRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    return _getRecords(
      collection,
    ).where((record) => record.id.value == id.value).firstOrNull;
  }

  @override
  Future<RecordPage> listRecords({
    required String collection,
    QueryExpression query = const QueryExpression(),
  }) async {
    final records =
        _getRecords(
            collection,
          ).where((record) => _matchesFilters(record, query.filters)).toList()
          ..sort((left, right) => _compareRecords(left, right, query.sort));
    final start = (query.pagination.page - 1) * query.pagination.perPage;
    final pageItems = records
        .skip(start)
        .take(query.pagination.perPage)
        .toList();

    return RecordPage(
      items: List.unmodifiable(pageItems),
      page: query.pagination.page,
      perPage: query.pagination.perPage,
      totalItems: records.length,
    );
  }

  @override
  Future<void> deleteRecord({
    required String collection,
    required RecordIdentifier id,
  }) async {
    _records[collection]?.removeWhere((record) => record.id.value == id.value);
  }

  List<Record> _getRecords(String collection) =>
      _records[collection] ?? const <Record>[];

  Record _recordWithStorageIdentifier(Record record) {
    if (record.id.value.trim().isNotEmpty) {
      return record;
    }

    final records = _getRecords(record.collection);
    var next = records.length + 1;
    var nextId = '${record.collection}_$next';
    while (records.any((existing) => existing.id.value == nextId)) {
      next += 1;
      nextId = '${record.collection}_$next';
    }

    return Record(
      collection: record.collection,
      id: RecordIdentifier(nextId),
      data: record.data,
    );
  }

  static bool _matchesFilters(Record record, List<QueryFilter> filters) {
    return filters.every((filter) {
      final value = _fieldValue(record, filter.field);

      return switch (filter.operator) {
        QueryOperator.equals => value == filter.value,
        QueryOperator.notEquals => value != filter.value,
        QueryOperator.greaterThan => _matchesRange(
          value,
          filter.value,
          (comparison) => comparison > 0,
        ),
        QueryOperator.greaterThanOrEquals => _matchesRange(
          value,
          filter.value,
          (comparison) => comparison >= 0,
        ),
        QueryOperator.lessThan => _matchesRange(
          value,
          filter.value,
          (comparison) => comparison < 0,
        ),
        QueryOperator.lessThanOrEquals => _matchesRange(
          value,
          filter.value,
          (comparison) => comparison <= 0,
        ),
      };
    });
  }

  static int _compareRecords(
    Record left,
    Record right,
    List<QuerySort> sort,
  ) {
    for (final instruction in sort) {
      final direction = instruction.direction == SortDirection.ascending
          ? 1
          : -1;
      final comparison =
          _compareValues(
            _fieldValue(left, instruction.field),
            _fieldValue(right, instruction.field),
          ) *
          direction;

      if (comparison != 0) {
        return comparison;
      }
    }

    return 0;
  }

  static Object? _fieldValue(Record record, String field) {
    if (field == 'id') {
      return record.id.value;
    }

    return record.data[field];
  }

  static bool _matchesRange(
    Object? left,
    Object? right,
    bool Function(int comparison) predicate,
  ) {
    if (left == null || right == null) {
      return false;
    }

    return predicate(_compareValues(left, right));
  }

  static int _compareValues(Object? left, Object? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    if (left is num && right is num) {
      return left.compareTo(right);
    }
    if (left is DateTime && right is DateTime) {
      return left.compareTo(right);
    }
    if (left is String && right is String) {
      return left.compareTo(right);
    }
    if (left is bool && right is bool) {
      return left == right ? 0 : (left ? 1 : -1);
    }

    return left.toString().compareTo(right.toString());
  }
}
