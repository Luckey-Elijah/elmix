import 'package:elmix_engine/elmix_engine.dart';
import 'package:elmix_sqlite/elmix_sqlite.dart';
import 'package:test/test.dart';

void main() {
  group('SqliteStorageAdapter', () {
    test('applies query filters and sorting when listing records', () async {
      final storage = SqliteStorageAdapter();

      await storage.saveRecord(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('draft_high'),
          data: <String, Object?>{'published': false, 'score': 100},
        ),
      );
      await storage.saveRecord(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('published_low'),
          data: <String, Object?>{'published': true, 'score': 10},
        ),
      );
      await storage.saveRecord(
        const Record(
          collection: 'posts',
          id: RecordIdentifier('published_high'),
          data: <String, Object?>{'published': true, 'score': 20},
        ),
      );

      final page = await storage.listRecords(
        collection: 'posts',
        query: const QueryExpression(
          filters: <QueryFilter>[
            QueryFilter(
              field: 'published',
              operator: QueryOperator.equals,
              value: true,
            ),
          ],
          sort: <QuerySort>[
            QuerySort(field: 'score', direction: SortDirection.descending),
          ],
        ),
      );

      expect(
        page.items.map((record) => record.id.value),
        <String>['published_high', 'published_low'],
      );
      expect(page.totalItems, 2);
    });
  });
}
