/// Client entrypoint compiled into the Admin Control Plane browser bundle.
library;

import 'package:elmix_admin/admin_app.dart';
import 'package:elmix_admin/elmix_admin.dart';
import 'package:elmix_admin/main.client.options.dart';
import 'package:elmix_admin/src/admin_ui/browser_admin_api_transport.dart';
import 'package:elmix_admin/src/admin_ui/browser_admin_session_store.dart';
import 'package:jaspr/client.dart';

void main() {
  Jaspr.initializeApp(options: defaultClientOptions);

  final api = AdminApiClient(
    baseUrl: Uri.base,
    transport: BrowserAdminApiTransport(),
  );
  runApp(
    AdminApp(
      controlPlane: AdminControlPlane(api),
      sessions: BrowserAdminSessionStore(),
    ),
  );
}
