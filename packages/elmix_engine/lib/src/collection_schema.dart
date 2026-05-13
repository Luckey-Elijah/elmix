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

/// The framework-level role a [SchemaField] plays, if any.
enum FieldSystemRole {
  /// A normal application-defined field.
  none,

  /// The required non-removable record identity field.
  recordIdentifier,

  /// The default created timestamp field.
  created,

  /// The default updated timestamp field.
  updated,
}

/// Persisted metadata for a field in a [CollectionSchema].
class SchemaField {
  /// Creates persisted metadata for a collection field.
  const SchemaField({
    required this.name,
    required this.type,
    this.required = false,
    this.removable = true,
    this.systemRole = .none,
    this.targetCollection,
  });

  /// Creates the required non-removable record identifier field.
  const SchemaField.recordIdentifier()
    : name = 'id',
      type = .text,
      required = true,
      removable = false,
      systemRole = .recordIdentifier,
      targetCollection = null;

  /// Creates the removable default created timestamp field.
  const SchemaField.created()
    : name = 'created',
      type = .date,
      required = false,
      removable = true,
      systemRole = .created,
      targetCollection = null;

  /// Creates the removable default updated timestamp field.
  const SchemaField.updated()
    : name = 'updated',
      type = .date,
      required = false,
      removable = true,
      systemRole = .updated,
      targetCollection = null;

  /// The field name.
  final String name;

  /// The field type.
  final FieldType type;

  /// Whether this field must be present for records in the collection.
  final bool required;

  /// Whether this field may be removed from the collection schema.
  final bool removable;

  /// The framework-level role this field plays.
  final FieldSystemRole systemRole;

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

  /// Creates a collection schema whose records can authenticate.
  const CollectionSchema.auth({
    required this.name,
    required this.fields,
    required this.accessRules,
  }) : isAuthCollection = true;

  /// The default fields seeded into new collection schemas.
  static List<SchemaField> defaultFields() {
    return const <SchemaField>[
      SchemaField.recordIdentifier(),
      SchemaField.created(),
      SchemaField.updated(),
    ];
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
