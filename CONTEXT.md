# Elmix

Elmix is a Dart-native backend framework for building PocketBase-like applications. This context captures the product language used to scope the framework and keep module boundaries aligned with the intended developer experience.

## Language

**PocketBase-like**:
A backend experience that preserves PocketBase's core mental model while prioritizing Dart-native extensibility over strict PocketBase compatibility.
_Avoid_: PocketBase clone, PocketBase-compatible

**Dart-native**:
Designed to be installed, embedded, extended, and typed from Dart without treating Dart as a wrapper around another runtime.
_Avoid_: Dart wrapper, Dart port

**Initial Product Loop**:
The smallest end-to-end experience that proves schema, records, auth rules, REST, admin basics, SQLite persistence, and Dart client usage work together.
_Avoid_: MVP, full PocketBase parity

**Engine**:
The framework kernel that owns Elmix application semantics while depending on abstract transport and storage contracts.
_Avoid_: Shared utilities, SQLite layer, HTTP layer

**Storage Adapter**:
A persistence implementation that satisfies the engine's storage contracts for a specific database.
_Avoid_: Database backend, engine storage

**Initial Module Set**:
The first-release package boundary that implements the Initial Product Loop without carrying future-only packages.
_Avoid_: Full package roadmap

**Admin Control Plane**:
The built-in administrative experience for managing schema, records, basic access rules, and administrator access.
_Avoid_: App builder, CMS, observability dashboard

**Access Rule**:
A persisted expression that decides whether a request may perform a collection operation.
_Avoid_: Auth rule, permission callback

**Admin Account**:
An operator identity used to access and manage the Elmix control plane.
_Avoid_: Admin user, admin auth record

**Auth Record**:
An application record in an auth-enabled collection that can authenticate into application APIs.
_Avoid_: User, user auth record, principal

**Auth Collection**:
A collection whose records can authenticate as Auth Records.
_Avoid_: User collection

**Collection Schema**:
Persisted runtime metadata that defines a collection's fields, constraints, auth capability, and access rules.
_Avoid_: Dart model, table definition

**Schema Field**:
A persisted field definition that belongs to a Collection Schema and participates in validation, persistence, API responses, and admin editing.
_Avoid_: Column, property

**Default System Field**:
A field seeded into new Collection Schemas by convention but not necessarily protected from removal.
_Avoid_: Required framework field, magic field

**Record Identifier**:
The required non-removable identity field for a record.
_Avoid_: Optional id, custom primary key

**Relation Field**:
A schema field that stores the Record Identifier of one record from one target collection.
_Avoid_: Join table, polymorphic relation, nested relation

**Public API**:
Application-facing REST endpoints for records, authentication, and collection access.
_Avoid_: PocketBase-compatible API

**Admin API**:
Control-plane endpoints used by the Admin Control Plane to manage Elmix itself.
_Avoid_: Direct schema mutation

**Dynamic Client**:
A Dart client that accesses collections by name and returns dynamic record data rather than generated models.
_Avoid_: Generated client, typed model client

**Schema Snapshot**:
A portable export or import of Collection Schemas used to move schema state between environments.
_Avoid_: Migration

**Embedded Mode**:
Using Elmix from a custom Dart executable rather than only through the CLI.
_Avoid_: Plugin framework, primary v0 product path

**Action Hook**:
A lifecycle extension point that runs before or after a collection or authentication action.
_Avoid_: Plugin, middleware, background job

**Query Expression**:
User-supplied criteria for listing records through pagination, sorting, and basic field comparisons.
_Avoid_: Full-text search, relation join query

**Schema Application**:
Applying Collection Schema changes to the active storage adapter so records can be persisted and queried.
_Avoid_: Migration, migration history

**Post-v0 Feature**:
A PocketBase-like capability intentionally excluded from the initial release while preserving architectural room for it later.
_Avoid_: Hidden v0 requirement

**Elmix Core v0**:
The first release scope that proves the PocketBase-like backend core loop with Dart-native architecture.
_Avoid_: Full Elmix, complete PocketBase-like surface

## Relationships

- **Elmix** is **PocketBase-like** but not **PocketBase-compatible** by default.
- **Dart-native** extensibility takes priority over exact PocketBase API parity.
- The **Initial Product Loop** excludes generated clients, files, realtime, advanced hooks, social auth, activity views, full migration tooling, and PocketBase import/export compatibility.
- The **Engine** owns collection, field, record, validation, auth rule, hook, execution context, and use-case semantics.
- The **Engine** depends on **Storage Adapter** contracts, not SQLite APIs or SQL strings.
- SQLite is the first supported **Storage Adapter**; other databases are possible but not promised by the initial release.
- The **Initial Module Set** consists of engine, SQLite adapter, server, admin, Dart client, and CLI packages.
- Generated clients and a standalone hooks package are outside the **Initial Module Set**.
- The **Admin Control Plane** manages the Initial Product Loop but does not include activity logs, API exploration, file management, realtime inspection, dashboard metrics, or CMS-style editing in the initial release.
- An **Access Rule** is authorization logic, distinct from authentication.
- Initial **Access Rule** expressions cover list, view, create, update, and delete collection operations.
- Initial **Access Rule** expressions can refer to auth state, current user id, record fields, request data fields, and basic boolean/comparison operators.
- **Admin Accounts** administer Elmix itself; **Auth Records** belong to application collections.
- An **Auth Record** belongs to exactly one **Auth Collection**.
- **Admin Accounts** and **Auth Records** are distinct identity concepts even if both use email/password credentials.
- Elmix supports multiple **Auth Collections** in the model; a starter project may still create a conventional `users` collection.
- A **Collection Schema** is dynamic and persisted, not defined primarily by Dart classes in the initial release.
- SQLite tables are derived from **Collection Schemas**.
- Initial **Schema Fields** include text, number, bool, date, email, password, select, relation, and json.
- File, rich text, URL, geo, and specialized field variants are outside the initial field set.
- `id` is the **Record Identifier** and is required for every record.
- `created` and `updated` are removable **Default System Fields** seeded into new Collection Schemas.
- Initial **Relation Fields** reference a single record in a single target collection.
- Multi-record relations, many-to-many join management, cascade behavior, polymorphic relations, and nested relation writes are outside the initial release.
- The **Public API** may use PocketBase-inspired paths while defining Elmix-owned behavior and response contracts.
- The **Admin Control Plane** uses the **Admin API** instead of mutating schema or records directly.
- The initial Dart client is a **Dynamic Client** for authentication, collection CRUD, pagination, and simple query options.
- Generated typed clients, offline sync, Flutter-specific token storage, realtime, files, and relation expansion helpers are outside the initial **Dynamic Client** scope.
- The initial CLI creates projects, serves apps, creates Admin Accounts, and imports or exports **Schema Snapshots**.
- Full migrations, generated clients, deployment commands, executable bundling, plugin management, backups, and process management are outside initial CLI scope.
- **Embedded Mode** is an architectural constraint for the initial release but not a polished primary product surface.
- Initial **Action Hooks** cover before and after list, view, create, update, and delete collection actions.
- Initial **Action Hooks** also cover before and after authentication.
- Collection **Access Rules** run before collection **Action Hooks**.
- Collection **Action Hooks** only run for authorized collection requests.
- App start and stop hooks, request middleware hooks, plugin registration APIs, async job queues, realtime fanout, and cross-module hook packages are outside initial hook scope.
- Initial **Query Expressions** support pagination, sorting, basic field comparisons, and boolean conjunction.
- Relation joins, full-text search, broad string search, and complex nested filtering are outside initial **Query Expression** scope.
- **Query Expressions** and **Access Rules** are distinct concepts even if they later share parser infrastructure.
- Initial SQLite **Schema Application** creates tables, adds fields, applies safe metadata changes, handles field removal where feasible, creates basic indexes, and persists Collection Schemas.
- User-authored migrations, rollbacks, migration graphs, data transforms, cross-environment diff planning, and zero-downtime guarantees are outside initial **Schema Application** scope.
- Files and realtime are **Post-v0 Features**.
- Initial architecture should avoid blocking future files or realtime, but the initial release does not implement file storage, file APIs, realtime subscriptions, realtime fanout, or realtime client support.
- **Elmix Core v0** includes dynamic schemas, records, authentication, Access Rules, Action Hooks, Public API, Admin API, SQLite persistence, Admin Control Plane basics, Dynamic Client, and CLI startup.
- **Elmix Core v0** excludes files, realtime, generated clients, full migrations, advanced admin tooling, OAuth, social auth, and a polished embedded/plugin framework.

## Example dialogue

> **Dev:** "Do we need to match PocketBase's API behavior exactly?"
> **Domain expert:** "No — Elmix should feel **PocketBase-like**, but the first release should optimize for **Dart-native** architecture and ergonomics."
>
> **Dev:** "Should realtime and generated clients be part of the first release?"
> **Domain expert:** "No — the **Initial Product Loop** is schema, records, auth rules, REST, admin basics, SQLite persistence, and Dart client usage."
>
> **Dev:** "Can the engine call SQLite directly if SQLite is the only supported database at launch?"
> **Domain expert:** "No — the **Engine** should orchestrate Elmix semantics through **Storage Adapter** contracts, with SQLite as the first adapter."
>
> **Dev:** "Should typed code generation be a package in the first release?"
> **Domain expert:** "No — the **Initial Module Set** should prove the product loop before adding generated clients or a standalone hooks package."
>
> **Dev:** "Is the admin UI supposed to be an app builder?"
> **Domain expert:** "No — the **Admin Control Plane** exists to manage schema, records, basic access rules, and administrator access."
>
> **Dev:** "Should permissions be Dart callbacks only?"
> **Domain expert:** "No — **Access Rules** need persisted expressions so the **Admin Control Plane** can edit them."
>
> **Dev:** "Are admin identities just records in a users collection?"
> **Domain expert:** "No — **Admin Accounts** operate Elmix, while **Auth Records** belong to the application domain."
>
> **Dev:** "Is `users` a framework requirement?"
> **Domain expert:** "No — `users` can be a starter convention, but Elmix supports multiple **Auth Collections**."
>
> **Dev:** "Do developers need to write Dart classes before creating collections?"
> **Domain expert:** "No — **Collection Schemas** are dynamic runtime metadata; typed Dart models can be generated later."
>
> **Dev:** "Are created and updated hardcoded framework fields?"
> **Domain expert:** "No — they are removable **Default System Fields** seeded into new schemas."
>
> **Dev:** "Can a collection remove its id field?"
> **Domain expert:** "No — `id` is the **Record Identifier** and stays required so APIs, relations, clients, and access rules have stable identity."
>
> **Dev:** "Can a relation field point to several records?"
> **Domain expert:** "No — an initial **Relation Field** stores one **Record Identifier** from one target collection."
>
> **Dev:** "Does using PocketBase-like REST paths make Elmix PocketBase-compatible?"
> **Domain expert:** "No — the **Public API** can feel familiar while still using Elmix-owned behavior and contracts."
>
> **Dev:** "Will the first Dart client generate models?"
> **Domain expert:** "No — the initial client is a **Dynamic Client** that uses collection names and dynamic record data."
>
> **Dev:** "Should schema import/export be called migrations?"
> **Domain expert:** "No — initial schema portability is through **Schema Snapshots**, not a full migration system."
>
> **Dev:** "Does v0 need a polished embedded API?"
> **Domain expert:** "No — **Embedded Mode** should influence architecture, but the CLI/server path is the primary initial product path."
>
> **Dev:** "Are hooks a plugin system?"
> **Domain expert:** "No — initial **Action Hooks** are engine lifecycle extension points for collection and authentication actions."
>
> **Dev:** "Can before-create hooks inspect unauthorized requests?"
> **Domain expert:** "No — collection **Access Rules** pass before collection **Action Hooks** run."
>
> **Dev:** "Can list queries join across relation fields?"
> **Domain expert:** "No — initial **Query Expressions** stay within basic field comparisons on the target collection."
>
> **Dev:** "Does schema import/export imply full migrations?"
> **Domain expert:** "No — v0 uses **Schema Application** and **Schema Snapshots**, not a migration history system."
>
> **Dev:** "Are files and realtime required because Elmix is PocketBase-like?"
> **Domain expert:** "No — files and realtime are **Post-v0 Features** even though they are important to the long-term PocketBase-like experience."
>
> **Dev:** "What are we actually trying to ship first?"
> **Domain expert:** "**Elmix Core v0** — the smallest Dart-native, PocketBase-like backend core loop."

## Flagged ambiguities

- "Near-fidelity of PocketBase" was resolved to mean architecture and ergonomics fidelity, not strict API or product parity.
- "Auth rule" was resolved to **Access Rule** because authentication identifies a requester while authorization decides what that requester may do.
- "User" was avoided as a framework identity term because application auth collections may represent members, customers, staff, devices, or other domain concepts.
