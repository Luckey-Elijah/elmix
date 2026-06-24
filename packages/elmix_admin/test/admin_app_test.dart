import 'package:elmix_admin/admin_app.dart';
import 'package:elmix_admin/elmix_admin.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_test/jaspr_test.dart';

void main() {
  testComponents(
    'asks the operator to sign in before showing any admin screen',
    (tester) {
      tester.pumpComponent(adminApp());

      expect(find.text('Sign in to Elmix'), findsOneComponent);
      expect(find.text('Collection Schemas'), findsNothing);
    },
  );

  testComponents('stores a successful login and opens Collection Schemas', (
    tester,
  ) async {
    final sessions = MemoryAdminSessionStore();
    tester.pumpComponent(adminApp(sessions: sessions));

    await tester.click(find.tag('button'));

    expect(sessions.readBearerToken(), 'admin-token');
    expect(find.text('Collection Schemas'), findsOneComponent);
    expect(find.text('Sign in to Elmix'), findsNothing);
    expect(
      find.text('Admin API response field "items" must be a list.'),
      findsNothing,
    );
  });

  testComponents(
    'restores an operator session and shows its Collection Schemas',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: CollectionSchemaListAdminApiTransport(),
        ),
      );

      await tester.pump();

      expect(find.text('Collection Schemas'), findsOneComponent);
      expect(find.text('posts'), findsOneComponent);
    },
  );

  testComponents(
    'keeps Admin Account collections out of Collection Schema management',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: AdminAccountAndCollectionSchemaListTransport(),
        ),
      );

      await tester.pump();

      expect(find.text('posts'), findsOneComponent);
      expect(find.text('_admins'), findsNothing);
    },
  );

  testComponents(
    'returns to sign in when a restored Admin session is no longer valid',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('expired-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: ExpiredSessionAdminApiTransport(),
        ),
      );

      await tester.pump();

      expect(find.text('Sign in to Elmix'), findsOneComponent);
      expect(sessions.readBearerToken(), isNull);
    },
  );

  testComponents(
    'offers a signed-in operator a Collection Schema creation form',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: CollectionSchemaListAdminApiTransport(),
        ),
      );

      await tester.pump();

      expect(find.text('Create Collection Schema'), findsOneComponent);
    },
  );

  testComponents(
    'explains why an operator cannot create an unnamed Collection Schema',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: CollectionSchemaListAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'Create collection'));

      expect(
        find.text('A Collection Schema name is required.'),
        findsOneComponent,
      );
    },
  );

  testComponents(
    'opens a listed Collection Schema for management',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: CollectionSchemaListAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'posts'));

      expect(find.text('posts Collection Schema'), findsOneComponent);
      expect(find.text('Schema Fields'), findsOneComponent);
    },
  );

  testComponents(
    'offers Schema Field creation from a Collection Schema',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: CollectionSchemaListAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'posts'));

      expect(find.text('Create Schema Field'), findsOneComponent);
    },
  );

  testComponents(
    'deletes a selected Collection Schema',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: CollectionSchemaListAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'posts'));
      await tester.click(
        find.componentWithText(button, 'Delete Collection Schema'),
      );

      expect(find.text('Collection Schemas'), findsOneComponent);
      expect(find.text('posts'), findsNothing);
    },
  );

  testComponents(
    'offers plain-text fields for every Access Rule operation',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: CollectionSchemaListAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'posts'));

      for (final operation in <String>[
        'List Access Rule',
        'View Access Rule',
        'Create Access Rule',
        'Update Access Rule',
        'Delete Access Rule',
      ]) {
        expect(find.text(operation), findsOneComponent);
      }
    },
  );

  testComponents(
    'offers generated Record creation from a Collection Schema',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: CollectionSchemaListAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'posts'));

      expect(find.text('Create Record'), findsOneComponent);
    },
  );

  testComponents(
    'offers Collection Schema settings for editing',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: CollectionSchemaListAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'posts'));

      expect(find.text('Collection Settings'), findsOneComponent);
      expect(find.text('Authentication Collection'), findsOneComponent);
    },
  );

  testComponents(
    'shows Schema Field validation errors on the selected schema screen',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: CollectionSchemaListAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'posts'));
      await tester.click(find.componentWithText(button, 'Save Schema Field'));

      expect(
        find.text('A Schema Field name is required.'),
        findsOneComponent,
      );
    },
  );

  testComponents(
    'opens a dedicated Admin Accounts screen without exposing _admins',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: AdminAccountsAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'Admin Accounts'));

      expect(find.text('Admin Accounts'), findsOneComponent);
      expect(find.text('admin@example.test'), findsOneComponent);
      expect(find.text('_admins'), findsNothing);
    },
  );

  testComponents(
    'offers Admin Account creation from the dedicated screen',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: AdminAccountsAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'Admin Accounts'));

      expect(find.text('Create Admin Account'), findsOneComponent);
    },
  );

  testComponents(
    'offers password change and deletion for listed Admin Accounts',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: AdminAccountsAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'Admin Accounts'));

      expect(find.text('Change Admin Account Password'), findsOneComponent);
      expect(find.text('Delete Admin Account'), findsOneComponent);
    },
  );

  testComponents(
    'shows a last-Admin-Account deletion rejection',
    (tester) async {
      final sessions = MemoryAdminSessionStore()
        ..saveBearerToken('saved-token');
      tester.pumpComponent(
        adminApp(
          sessions: sessions,
          transport: LastAdminAccountAdminApiTransport(),
        ),
      );

      await tester.pump();
      await tester.click(find.componentWithText(button, 'Admin Accounts'));
      await tester.click(
        find.componentWithText(button, 'Delete Admin Account'),
      );

      expect(
        find.text('The last remaining Admin Account cannot be deleted.'),
        findsOneComponent,
      );
    },
  );
}

AdminApp adminApp({
  AdminSessionStore? sessions,
  AdminApiTransport? transport,
}) {
  return AdminApp(
    controlPlane: AdminControlPlane(
      AdminApiClient(
        baseUrl: Uri.parse('http://localhost'),
        transport: transport ?? LoginAdminApiTransport(),
      ),
    ),
    sessions: sessions ?? MemoryAdminSessionStore(),
  );
}

class LoginAdminApiTransport extends AdminApiTransport {
  @override
  Future<AdminApiResponse> send(AdminApiRequest request) async {
    if (request.url.path == '/api/admin/collections') {
      return const AdminApiResponse(
        statusCode: 200,
        body: <String, Object?>{'items': <Object?>[]},
      );
    }
    return const AdminApiResponse(
      statusCode: 200,
      body: <String, Object?>{
        'token': 'admin-token',
        'admin': <String, Object?>{
          'id': 'admin_1',
          'email': 'admin@example.test',
        },
      },
    );
  }
}

class CollectionSchemaListAdminApiTransport extends AdminApiTransport {
  @override
  Future<AdminApiResponse> send(AdminApiRequest request) async {
    return const AdminApiResponse(
      statusCode: 200,
      body: <String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'name': 'posts',
            'isAuthCollection': false,
            'fields': <Object?>[],
            'accessRules': <String, Object?>{},
          },
        ],
      },
    );
  }
}

class AdminAccountAndCollectionSchemaListTransport extends AdminApiTransport {
  @override
  Future<AdminApiResponse> send(AdminApiRequest request) async {
    return const AdminApiResponse(
      statusCode: 200,
      body: <String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'name': '_admins',
            'isAuthCollection': false,
            'fields': <Object?>[],
            'accessRules': <String, Object?>{},
          },
          <String, Object?>{
            'name': 'posts',
            'isAuthCollection': false,
            'fields': <Object?>[],
            'accessRules': <String, Object?>{},
          },
        ],
      },
    );
  }
}

class ExpiredSessionAdminApiTransport extends AdminApiTransport {
  @override
  Future<AdminApiResponse> send(AdminApiRequest request) async {
    return const AdminApiResponse(
      statusCode: 401,
      body: <String, Object?>{
        'error': <String, Object?>{
          'code': 'admin_session_required',
          'message': 'Admin session is required.',
        },
      },
    );
  }
}

class AdminAccountsAdminApiTransport extends AdminApiTransport {
  @override
  Future<AdminApiResponse> send(AdminApiRequest request) async {
    if (request.url.path == '/api/admin/accounts') {
      return const AdminApiResponse(
        statusCode: 200,
        body: <String, Object?>{
          'items': <Object?>[
            <String, Object?>{
              'id': 'admin@example.test',
              'email': 'admin@example.test',
            },
          ],
        },
      );
    }
    return const AdminApiResponse(
      statusCode: 200,
      body: <String, Object?>{'items': <Object?>[]},
    );
  }
}

class LastAdminAccountAdminApiTransport extends AdminAccountsAdminApiTransport {
  @override
  Future<AdminApiResponse> send(AdminApiRequest request) async {
    if (request.method == 'DELETE') {
      return const AdminApiResponse(
        statusCode: 409,
        body: <String, Object?>{
          'error': <String, Object?>{
            'code': 'last_admin_account',
            'message': 'The last remaining Admin Account cannot be deleted.',
          },
        },
      );
    }
    return super.send(request);
  }
}
