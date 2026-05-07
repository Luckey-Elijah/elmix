import 'access_rule.dart';

/// The initial field types supported by Elmix Core v0.
enum FieldType {
  text,
  number,
  bool,
  date,
  email,
  password,
  select,
  relation,
  json,
}

/// Persisted metadata for a field in a [CollectionSchema].
final class SchemaField {
  const SchemaField({
    required this.name,
    required this.type,
    this.required = false,
    this.targetCollection,
  });

  final String name;
  final FieldType type;
  final bool required;

  /// The target collection for relation fields.
  final String? targetCollection;
}

/// Persisted runtime metadata that defines a collection.
final class CollectionSchema {
  const CollectionSchema({
    required this.name,
    required this.fields,
    required this.accessRules,
    this.isAuthCollection = false,
  });

  final String name;
  final List<SchemaField> fields;
  final Map<CollectionOperation, AccessRule> accessRules;
  final bool isAuthCollection;
}
