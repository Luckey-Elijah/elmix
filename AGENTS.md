# Agent Instructions

## Dart API Extensibility

Do not define exclusive or restrictive Dart class modifiers unless explicitly requested for that specific type.

Avoid:

- `final class`
- `sealed class`
- `base class`
- `interface class`
- `abstract interface class`
- `abstract base class`
- `abstract final class`

Prefer ordinary `class` or `abstract class` declarations so downstream consumers can extend, implement, mock, and adapt Elmix APIs as needed.

