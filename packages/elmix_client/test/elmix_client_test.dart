import 'package:elmix_client/elmix_client.dart';
import 'package:test/test.dart';

void main() {
  group('Fluent query builder', () {
    test('sends chained filters, sorting, and pagination', () async {
      final transport = CapturingTransport(
        const ElmixClientResponse(
          statusCode: 200,
          body: <String, Object?>{
            'page': 2,
            'perPage': 10,
            'totalItems': 42,
            'items': <Object?>[
              <String, Object?>{
                'collection': 'posts',
                'id': 'post_1',
                'data': <String, Object?>{
                  'id': 'shadowed',
                  'title': 'Hello',
                  'views': 12,
                  'published': true,
                },
              },
            ],
          },
        ),
      );
      final client = ElmixClient(
        Uri.parse('https://example.test'),
        transport: transport,
      );

      final page = await client
          .collection('posts')
          .list()
          .eq('published', true)
          .gte('views', 10)
          .desc('created')
          .page(2, perPage: 10)
          .send();

      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.method, 'GET');
      expect(
        transport.requests.single.url.toString(),
        startsWith('https://example.test/api/collections/posts/records?'),
      );
      expect(transport.requests.single.query, <String, Object?>{
        'filters': <Object?>[
          <String, Object?>{
            'field': 'published',
            'operator': 'equals',
            'value': true,
          },
          <String, Object?>{
            'field': 'views',
            'operator': 'greaterThanOrEquals',
            'value': 10,
          },
        ],
        'sort': <Object?>[
          <String, Object?>{
            'field': 'created',
            'direction': 'descending',
          },
        ],
        'pagination': <String, Object?>{'page': 2, 'perPage': 10},
      });
      expect(page.page, 2);
      expect(page.perPage, 10);
      expect(page.totalItems, 42);
      expect(page.items.single.collection, 'posts');
      expect(page.items.single.id, 'post_1');
      expect(page.items.single.data, <String, Object?>{
        'id': 'post_1',
        'title': 'Hello',
        'views': 12,
        'published': true,
      });
    });

    test('supports all v0 comparison and sort helpers', () async {
      final transport = CapturingTransport(
        const ElmixClientResponse(
          statusCode: 200,
          body: <String, Object?>{
            'page': 1,
            'perPage': 30,
            'totalItems': 0,
            'items': <Object?>[],
          },
        ),
      );
      final client = ElmixClient(
        Uri.parse('https://example.test'),
        transport: transport,
      );

      await client
          .collection('posts')
          .list()
          .eq('status', 'published')
          .neq('author', 'blocked')
          .gt('views', 100)
          .gte('score', 10)
          .lt('created', '2026-05-12T00:00:00.000Z')
          .lte('comments', 25)
          .asc('title')
          .desc('created')
          .send();

      expect(
        (transport.requests.single.query['filters']! as List<Object?>).map(
          (filter) => (filter! as Map<String, Object?>)['operator'],
        ),
        <String>[
          'equals',
          'notEquals',
          'greaterThan',
          'greaterThanOrEquals',
          'lessThan',
          'lessThanOrEquals',
        ],
      );
      expect(transport.requests.single.query['sort'], <Object?>[
        <String, Object?>{'field': 'title', 'direction': 'ascending'},
        <String, Object?>{'field': 'created', 'direction': 'descending'},
      ]);
    });
  });

  group('Dynamic collection records', () {
    test('views, creates, updates, and deletes records', () async {
      final transport = QueueTransport(<ElmixClientResponse>[
        const ElmixClientResponse(
          statusCode: 200,
          body: <String, Object?>{
            'collection': 'posts',
            'id': 'post_1',
            'data': <String, Object?>{'title': 'Draft'},
          },
        ),
        const ElmixClientResponse(
          statusCode: 201,
          body: <String, Object?>{
            'collection': 'posts',
            'id': 'post_2',
            'data': <String, Object?>{'title': 'New draft'},
          },
        ),
        const ElmixClientResponse(
          statusCode: 200,
          body: <String, Object?>{
            'collection': 'posts',
            'id': 'post_2',
            'data': <String, Object?>{'title': 'Published'},
          },
        ),
        const ElmixClientResponse(statusCode: 204),
      ]);
      final client = ElmixClient(
        Uri.parse('https://example.test'),
        transport: transport,
      )..bearerToken = 'token_123';
      final posts = client.collection('posts');

      final viewed = await posts.view('post_1');
      final created = await posts.create(<String, Object?>{
        'id': 'post_2',
        'title': 'New draft',
      });
      final updated = await posts.update('post_2', <String, Object?>{
        'title': 'Published',
      });
      await posts.delete('post_2');

      expect(viewed.data['id'], 'post_1');
      expect(created.data, <String, Object?>{
        'id': 'post_2',
        'title': 'New draft',
      });
      expect(updated.data, <String, Object?>{
        'id': 'post_2',
        'title': 'Published',
      });
      expect(
        transport.requests.map((request) => request.method),
        <String>['GET', 'POST', 'PATCH', 'DELETE'],
      );
      expect(
        transport.requests.map((request) => request.url.path),
        <String>[
          '/api/collections/posts/records/post_1',
          '/api/collections/posts/records',
          '/api/collections/posts/records/post_2',
          '/api/collections/posts/records/post_2',
        ],
      );
      expect(transport.requests[1].body, <String, Object?>{
        'id': 'post_2',
        'data': <String, Object?>{'title': 'New draft'},
      });
      expect(transport.requests[2].body, <String, Object?>{
        'data': <String, Object?>{'title': 'Published'},
      });
      expect(
        transport.requests.map((request) => request.headers['authorization']),
        everyElement('Bearer token_123'),
      );
    });
  });

  group('Auth Records', () {
    test('authenticates with email/password and stores bearer token', () async {
      final transport = QueueTransport(<ElmixClientResponse>[
        const ElmixClientResponse(
          statusCode: 200,
          body: <String, Object?>{
            'token': 'token_123',
            'record': <String, Object?>{
              'collection': 'members',
              'id': 'member_1',
              'data': <String, Object?>{'email': 'ada@example.com'},
            },
          },
        ),
      ]);
      final client = ElmixClient(
        Uri.parse('https://example.test'),
        transport: transport,
      );

      final auth = await client
          .collection('members')
          .authWithPassword(
            email: 'ada@example.com',
            password: 'correct horse',
          );

      expect(client.bearerToken, 'token_123');
      expect(auth.token, 'token_123');
      expect(auth.record.data, <String, Object?>{
        'id': 'member_1',
        'email': 'ada@example.com',
      });
      expect(transport.requests.single.method, 'POST');
      expect(
        transport.requests.single.url.path,
        '/api/collections/members/auth-with-password',
      );
      expect(transport.requests.single.body, <String, Object?>{
        'email': 'ada@example.com',
        'password': 'correct horse',
      });
    });
  });

  group('Elmix error contracts', () {
    test('exposes server error code and message', () async {
      final transport = QueueTransport(<ElmixClientResponse>[
        const ElmixClientResponse(
          statusCode: 403,
          body: <String, Object?>{
            'error': <String, Object?>{
              'code': 'forbidden',
              'message': 'Collection "posts" list request is not authorized.',
            },
          },
        ),
      ]);
      final client = ElmixClient(
        Uri.parse('https://example.test'),
        transport: transport,
      );

      await expectLater(
        client.collection('posts').list().send(),
        throwsA(
          isA<ElmixClientException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having((error) => error.code, 'code', 'forbidden')
              .having(
                (error) => error.message,
                'message',
                'Collection "posts" list request is not authorized.',
              ),
        ),
      );
    });
  });
}

class CapturingTransport implements ElmixClientTransport {
  CapturingTransport(this.response);

  final ElmixClientResponse response;
  final List<ElmixClientRequest> requests = <ElmixClientRequest>[];

  @override
  Future<ElmixClientResponse> send(ElmixClientRequest request) async {
    requests.add(request);
    return response;
  }
}

class QueueTransport implements ElmixClientTransport {
  QueueTransport(this.responses);

  final List<ElmixClientResponse> responses;
  final List<ElmixClientRequest> requests = <ElmixClientRequest>[];

  @override
  Future<ElmixClientResponse> send(ElmixClientRequest request) async {
    requests.add(request);
    return responses.removeAt(0);
  }
}
