# Contributing to Elmix

## Consumer-extensible Dart APIs

Elmix is Dart-native and consumer-extensible by default. Downstream developers
should be able to extend, implement, mock, wrap, and adapt Elmix APIs as their
applications require.

Use ordinary `class` and `abstract class` declarations by default. Do not
introduce these restrictive Dart class modifiers without an explicit,
type-specific API decision:

- `final class`
- `sealed class`
- `base class`
- `interface class`
- `abstract interface class`
- `abstract base class`
- `abstract final class`

A restrictive modifier is allowed only when it was explicitly requested for
that specific type and its API reason is documented near the decision. It is
not a default style choice. When in doubt, keep the type consumer-extensible.
