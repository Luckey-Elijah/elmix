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

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `Luckey-Elijah/elmix`. See `docs/agents/issue-tracker.md`.

### Triage labels

Triage labels use the default mattpocock/skills vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain docs layout. See `docs/agents/domain.md`.
