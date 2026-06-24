# Elmix

Elmix is a Dart-native, self-contained backend framework with dynamic schemas, SQLite-backed persistence, REST/admin APIs, an admin control plane, and a Dart client.

## Inspiration

Elmix is inspired by PocketBase's compact backend experience: dynamic collections, built-in admin tooling, SQLite simplicity, and easy client access. It is not a PocketBase clone, and Elmix Core v0 does not target PocketBase API or behavior compatibility.

## Elmix Core v0

Elmix Core v0 is the first release scope. It proves the smallest end-to-end backend loop:

1. Create and edit dynamic collection schemas.
2. Store records in SQLite.
3. Authenticate application records from auth-enabled collections.
4. Protect collection operations with persisted access rules.
5. Expose collection CRUD and auth through a public REST API.
6. Manage schemas, records, rules, and admin access through an admin control plane.
7. Consume the server from a dynamic Dart client.
8. Create, serve, and move schema snapshots through a CLI.

This scope is intentionally smaller than the full long-term Elmix vision. It is the core product loop, not the complete backend platform surface.

## Contributor verification

Elmix public APIs stay consumer-extensible by default. Before handing off Dart
changes, run the standard checks and the restrictive-class-modifier check:

```bash
dart analyze
dart test
dart run tool/check_restrictive_class_modifiers.dart
```

The modifier check scans package source and retained prototype source. It fails
when it finds a restrictive Dart class declaration so the extensibility rule is
preserved before review.

## Product Shape

Elmix Core v0 is dynamic schema-first. Collections and fields are runtime metadata that can be managed through admin APIs and persisted by the storage adapter. Dart model generation can be added later after the schema model is stable.

The first supported storage adapter is SQLite. The engine must not depend on SQLite APIs or SQL strings, so future adapters such as Postgres or MySQL remain possible, but Core v0 only promises SQLite support.

The primary usage path is CLI/server-first:

```bash
elmix create my_app
cd my_app
elmix serve
```

Embedded mode should influence the architecture, but it is not a polished v0 product surface:

```dart
final app = ElmixApp(...);
await app.serve(port: 8090);
```

## Initial Modules

### `elmix_engine`

The framework kernel.

Owns:

- collection schemas
- field definitions
- record validation
- auth-enabled collection semantics
- access rule evaluation
- action hook lifecycle
- execution context
- storage contracts
- use-case orchestration for list, view, create, update, and delete

Does not own:

- HTTP routing
- JSON endpoint formatting
- SQLite SQL generation
- admin UI behavior
- CLI commands
- client transport

The engine owns Elmix semantics while depending on abstract storage and transport contracts.

### `elmix_sqlite`

The default storage adapter.

Owns:

- SQLite connection management
- collection table creation
- schema application
- basic indexes
- relation storage
- record serialization and deserialization
- transactions
- collection schema metadata persistence

Core v0 uses schema application, not a full migration system. It can create tables, add fields, apply safe metadata changes, handle field removal where feasible, and persist collection schemas.

### `elmix_server`

The HTTP server layer, likely built on `shelf`.

Owns:

- public REST API routing
- admin API routing
- auth/session handling
- request context creation
- collection CRUD endpoints
- auth endpoints
- middleware pipeline
- error formatting

The public API may use familiar collection-oriented paths while keeping Elmix-owned behavior and response contracts:

```text
GET    /api/collections/:collection/records
POST   /api/collections/:collection/records
GET    /api/collections/:collection/records/:id
PATCH  /api/collections/:collection/records/:id
DELETE /api/collections/:collection/records/:id
POST   /api/collections/:collection/auth-with-password
```

### `elmix_admin`

The built-in admin control plane, likely built with Jaspr.

Owns:

- admin login
- collection list
- create/edit/delete collection
- create/edit/delete fields
- record browser
- create/edit/delete records
- basic access rule editor
- admin account management where needed to avoid CLI-only lockout

The admin UI communicates through admin APIs instead of directly mutating schema or storage state.

### `elmix_client`

The dynamic Dart client SDK.

Owns:

- connecting to an Elmix server
- email/password auth for auth records
- bearer token handling in memory by default
- dynamic collection CRUD
- list pagination
- simple query options when supported by the public API
- logout/clear auth state

Example:

```dart
final client = ElmixClient('http://localhost:8090');

await client.collection('users').authWithPassword(
  'user@example.com',
  'password',
);

final posts = await client.collection('posts').getList();
await client.collection('posts').create({'title': 'Hello'});
```

### `elmix_cli`

The command-line tool.

Owns:

- `elmix create <app>`
- `elmix serve`
- `elmix admin create`
- `elmix schema export`
- `elmix schema import`

Schema import/export is a schema snapshot workflow, not full migrations.

## Core Concepts

### Collections and Fields

Collection schemas are persisted runtime metadata. They define fields, constraints, auth capability, and access rules.

Initial field types:

- `text`
- `number`
- `bool`
- `date`
- `email`
- `password`
- `select`
- `relation`
- `json`

Every record has a required, non-removable `id` record identifier.

New collection schemas are seeded with removable `created` and `updated` fields by convention.

Initial relation fields reference one record in one target collection. Multi-record relations, many-to-many join management, cascade behavior, polymorphic relations, and nested relation writes are post-v0 concerns.

### Identity

Elmix separates control-plane identity from application identity.

- Admin Accounts operate Elmix itself.
- Auth Records belong to application collections.
- Auth Collections are collections whose records can authenticate into application APIs.

Elmix supports multiple auth collections in the model. A starter project may create a conventional `users` collection, but the framework must not require one.

Core v0 supports email/password auth for auth records and separate admin login for admin accounts. OAuth, social auth, MFA, email verification, password reset, and anonymous persisted users are outside the initial scope.

### Access Rules

Access rules are persisted authorization expressions attached to collection operations.

Core v0 access rules cover:

- list
- view
- create
- update
- delete

Initial expressions can refer to auth state, current auth record id, record fields, request data fields, and basic boolean/comparison operators.

Access rules are distinct from authentication. Authentication identifies the requester; access rules decide what that requester may do.

### Action Hooks

Action hooks are engine lifecycle extension points, not a plugin system.

Core v0 hooks cover before and after:

- list
- view
- create
- update
- delete
- authentication

Collection access rules run before collection action hooks. Hooks only run for authorized collection requests.

### Query Expressions

Core v0 list queries support a minimal query model:

- pagination
- sorting
- basic field comparisons
- boolean conjunction

Relation joins, full-text search, broad string search, and complex nested filtering are outside the initial query scope.

## Post-v0 Roadmap

The following are important to the longer-term Elmix vision but intentionally excluded from Elmix Core v0:

- file fields, file APIs, file storage, and access-controlled file serving
- realtime subscriptions and realtime client support
- generated typed Dart clients
- standalone hooks package
- full migration history and rollback system
- user-authored migrations
- OAuth and social auth
- email verification and password reset flows
- advanced admin dashboards, logs, activity views, API explorer, and CMS-style editing
- deployment commands
- executable bundling
- plugin management
- backups and restore tooling
- polished embedded/plugin framework

The architecture should avoid blocking these features, but they are not acceptance criteria for the first release.

Keep the workspace itself within the Initial Module Set while Core v0 is in
development:

```bash
dart run tool/check_core_v0_scope.dart
```

Adding a future-only package requires an explicit product decision rather than
quietly widening the release scope.
