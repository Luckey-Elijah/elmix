import 'dart:convert';

import 'package:elmix_admin/src/admin_control_plane.dart';
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Browser transport that sends Admin API requests to the current Elmix origin.
class BrowserAdminApiTransport extends AdminApiTransport {
  /// Creates a browser Admin API transport.
  BrowserAdminApiTransport({http.Client? client})
    : _client = client ?? BrowserClient();

  final http.Client _client;

  @override
  Future<AdminApiResponse> send(AdminApiRequest request) async {
    final httpRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request.body != null) {
      httpRequest.headers['content-type'] = 'application/json';
      httpRequest.body = jsonEncode(request.body);
    }

    final response = await _client.send(httpRequest);
    final text = await response.stream.bytesToString();
    return AdminApiResponse(
      statusCode: response.statusCode,
      body: text.isEmpty ? null : jsonDecode(text),
    );
  }
}
