import 'package:elmix_admin/src/admin_ui/record_form_values.dart';
import 'package:elmix_engine/elmix_engine.dart';
import 'package:test/test.dart';

void main() {
  test('parses JSON form values before creating a record', () {
    final values = RecordFormValues.parse(
      fields: const <SchemaField>[
        SchemaField(name: 'metadata', type: .json),
      ],
      rawValues: const <String, String>{
        'metadata': '{"published":true,"tags":["dart"]}',
      },
    );

    expect(values, <String, Object?>{
      'metadata': <String, Object?>{
        'published': true,
        'tags': <Object?>['dart'],
      },
    });
  });

  test('rejects malformed JSON record form values', () {
    expect(
      () => RecordFormValues.parse(
        fields: const <SchemaField>[
          SchemaField(name: 'metadata', type: .json),
        ],
        rawValues: const <String, String>{
          'metadata': '{not-json}',
        },
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Field "metadata" must contain valid JSON.',
        ),
      ),
    );
  });

  test('writes false for an unchecked required boolean field', () {
    final values = RecordFormValues.parse(
      fields: const <SchemaField>[
        SchemaField(name: 'published', type: .bool, required: true),
      ],
      rawValues: const <String, String>{},
    );

    expect(values, <String, Object?>{'published': false});
  });

  test('allows an unchanged required password when editing a record', () {
    final values = RecordFormValues.parse(
      fields: const <SchemaField>[
        SchemaField(name: 'password', type: .password, required: true),
      ],
      rawValues: const <String, String>{},
      allowEmptyFields: const <String>{'password'},
    );

    expect(values, isEmpty);
  });
}
