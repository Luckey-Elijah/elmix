# Admin Package Owns Release-Built Control Plane Assets

The `elmix_admin` package owns the Jaspr Admin Control Plane source and the
version-matched browser assets generated from it. Its package-local build tool
creates the checked-in asset bundle used at runtime.

`elmix_cli` depends on that package only to serve its known assets at
`/_/admin`. It does not invoke Jaspr, resolve a separate artifact, or require
an Elmix operator to install a browser build tool. Browser code communicates
with Elmix exclusively through the Admin API.

This keeps the normal operator path as `elmix serve` while leaving the
maintainer workflow local and reproducible: develop with Jaspr from
`elmix_admin`, then regenerate the package-owned release bundle before
committing it.
