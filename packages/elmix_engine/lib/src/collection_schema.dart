import 'package:elmix_engine/src/access_rule.dart';

/// The initial field types supported by Elmix Core v0.
enum FieldType {
  /// Free-form text.
  text,

  /// Numeric values.
  number,

  /// Boolean values.
  bool,

  /// Date or date-time values.
  date,

  /// Email address values.
  email,

  /// Password or secret values.
  password,

  /// Values selected from a configured option set.
  select,

  /// References to records in another collection.
  relation,

  /// Structured JSON data.
  json,
}

/// Persisted metadata for a field in a [CollectionSchema].
class SchemaField {
  /// Creates persisted metadata for a collection field.
  const SchemaField({
    required this.name,
    required this.type,
    this.required = false,
    this.targetCollection,
  });

  /// The field name.
  final String name;

  /// The field type.
  final FieldType type;

  /// Whether this field must be present for records in the collection.
  final bool required;

  /// The target collection for relation fields.
  final String? targetCollection;
}

/// Persisted runtime metadata that defines a collection.
class CollectionSchema {
  /// Creates persisted runtime metadata for a collection.
  const CollectionSchema({
    required this.name,
    required this.fields,
    required this.accessRules,
    this.isAuthCollection = false,
  });

  /// Creates a schema with conventional removable system field metadata.
  factory CollectionSchema.withDefaultSystemFields({
    required String name,
    required List<SchemaField> fields,
    required Map<CollectionOperation, AccessRule> accessRules,
    bool isAuthCollection = false,
  }) {
    return CollectionSchema(
      name: name,
      fields: [
        const SchemaField(name: 'created', type: FieldType.date),
        const SchemaField(name: 'updated', type: FieldType.date),
        ...fields,
      ],
      accessRules: accessRules,
      isAuthCollection: isAuthCollection,
    );
  }

  /// The collection name.
  final String name;

  /// The fields stored by records in the collection.
  final List<SchemaField> fields;

  /// The access rules keyed by collection operation.
  final Map<CollectionOperation, AccessRule> accessRules;

  /// Whether this collection stores authentication records.
  final bool isAuthCollection;
}

/// Thrown when a collection schema cannot be registered or updated.
class CollectionSchemaException implements Exception {
  /// Creates a schema failure with a human-readable [message].
  const CollectionSchemaException(this.message);

  /// Describes why the schema operation failed.
  final String message;

  @override
  String toString() => 'CollectionSchemaException: $message';
}
