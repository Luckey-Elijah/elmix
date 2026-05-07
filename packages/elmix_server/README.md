# elmix_server

HTTP and admin API server layer for Elmix.

This package owns Public API routing, Admin API routing, request context creation, auth/session handling, and error formatting. It should depend on the Engine instead of reaching into storage adapters directly.

