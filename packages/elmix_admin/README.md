# elmix_admin

Admin control plane for Elmix.

This package owns the administrative experience for managing schemas, records, basic Access Rules, and Admin Accounts. It should communicate through Admin APIs rather than mutating storage directly.

Trusted setup and recovery paths use Admin Bootstrap helpers, which are distinct from the Admin Control Plane itself.
