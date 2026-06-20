import 'package:elmix_client/elmix_client.dart';
import 'package:test/test.dart';

void main() {
  test('a consumer can extend the client and adapt its transport', () async {
    final transport = ConsumerTransport();
    final client = ConsumerClient(transport: transport);

    final record = await client.collection('posts').view('post-1');

    expect(client.productName, 'consumer app');
    expect(record.id, 'post-1');
    expect(
      transport.lastRequest?.url.path,
      '/api/collections/posts/records/post-1',
    );
  });
}

class ConsumerClient extends ElmixClient {
  ConsumerClient({required super.transport})
    : super(Uri.parse('https://elmix.test'));

  String get productName => 'consumer app';
}

class ConsumerTransport implements ElmixClientTransport {
  ElmixClientRequest? lastRequest;

  @override
  Future<ElmixClientResponse> send(ElmixClientRequest request) async {
    lastRequest = request;
    return const ElmixClientResponse(
      statusCode: 200,
      body: {
        'collection': 'posts',
        'id': 'post-1',
        'data': {'title': 'Extensible'},
      },
    );
  }
}
