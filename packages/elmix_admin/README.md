# elmix_admin

Admin control plane for Elmix.

This package owns the administrative experience for managing schemas, records, and basic Access Rules. It should communicate through Admin APIs rather than mutating storage directly. Admin Account management is tracked separately from this initial control-plane slice.

Trusted setup and recovery paths use Admin Bootstrap helpers, which are distinct from the Admin Control Plane itself.

## Maintaining the browser bundle

The Admin Control Plane is authored here as a Jaspr client application. Elmix
operators do not install Jaspr or run a separate web server: `elmix serve`
serves the release-built bundle at `/_/admin`.

For local UI development, run the Jaspr development server from this package:

```sh
dart run jaspr_cli:jaspr serve
```

Before committing Admin UI changes, regenerate the package-owned release
assets:

```sh
dart run tool/build_admin.dart
```

That command runs the package-local Jaspr build and updates
`lib/src/generated/admin_assets.g.dart`, which the CLI serves as its embedded
Admin Control Plane asset bundle.
