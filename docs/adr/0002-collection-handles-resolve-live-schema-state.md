# Collection Handles Resolve Live Schema State

Elmix collection handles are live references to a collection name, not snapshots of a Collection Schema. When a Collection Schema is updated after a handle has been created, schema-dependent operations through that held handle must resolve and use the current registered schema at operation time, so writes such as create, save, and update validate against the latest runtime metadata instead of stale fields or constraints.

Operations that do not currently depend on schema semantics, such as get, list, and delete, do not need to fetch or validate the schema just to satisfy this decision. They may become schema-aware later if access rules, hooks, projection, relation behavior, or other engine semantics require it. Collection rename and removal behavior is intentionally out of scope until those operations are defined.
