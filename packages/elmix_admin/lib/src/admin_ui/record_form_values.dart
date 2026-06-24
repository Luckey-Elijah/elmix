import 'dart:convert';

import 'package:elmix_engine/elmix_engine.dart';

/// Converts browser record form input into Engine record data.
class RecordFormValues {
  /// Parses [rawValues] according to the supplied [fields].
  static Map<String, Object?> parse({
    required List<SchemaField> fields,
    required Map<String, String> rawValues,
    Set<String> allowEmptyFields = const <String>{},
  }) {
    final values = <String, Object?>{};
    for (final field in fields) {
      if (field.systemRole == .recordIdentifier) {
        continue;
      }

      final rawValue = rawValues[field.name]?.trim() ?? '';
      if (field.type == .bool && rawValue.isEmpty) {
        values[field.name] = false;
        continue;
      }
      if (rawValue.isEmpty) {
        if (allowEmptyFields.contains(field.name)) {
          continue;
        }
        if (field.required) {
          throw FormatException('Field "${field.name}" is required.');
        }
        continue;
      }
      values[field.name] = _parseFieldValue(field, rawValue);
    }
    return values;
  }

  static Object? _parseFieldValue(SchemaField field, String rawValue) {
    return switch (field.type) {
      .text || .email || .password || .select || .relation => rawValue,
      .number => _parseNumber(field, rawValue),
      .bool => rawValue == 'true',
      .date => _parseDate(field, rawValue),
      .json => _parseJson(field, rawValue),
    };
  }

  static num _parseNumber(SchemaField field, String rawValue) {
    final value = num.tryParse(rawValue);
    if (value == null) {
      throw FormatException('Field "${field.name}" must be a number.');
    }
    return value;
  }

  static DateTime _parseDate(SchemaField field, String rawValue) {
    final value = DateTime.tryParse(rawValue);
    if (value == null) {
      throw FormatException('Field "${field.name}" must be a date.');
    }
    return value;
  }

  static Object? _parseJson(SchemaField field, String rawValue) {
    try {
      return _jsonValue(jsonDecode(rawValue));
    } on FormatException {
      throw FormatException('Field "${field.name}" must contain valid JSON.');
    }
  }

  static Object? _jsonValue(Object? value) => switch (value) {
    final Map<Object?, Object?> map => <String, Object?>{
      for (final entry in map.entries)
        if (entry.key is String) entry.key! as String: _jsonValue(entry.value),
    },
    final List<Object?> list => list.map(_jsonValue).toList(),
    _ => value,
  };
}
