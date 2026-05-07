# Keep Engine Storage and Transport Independent

Elmix's engine will own application semantics such as collections, fields, records, validation, auth rules, hooks, execution context, and use-case orchestration, but it will not depend on HTTP, SQLite, or SQL strings. SQLite is the first supported storage adapter, while the engine boundary should leave room for future adapters such as Postgres or MySQL without making multi-database support a v0 requirement.
