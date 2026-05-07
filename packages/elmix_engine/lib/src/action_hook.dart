import 'access_rule.dart';
import 'record.dart';

/// Whether an [ActionHook] runs before or after the operation.
enum HookPhase { before, after }

/// Context passed to collection lifecycle hooks.
class ActionHookContext {
  const ActionHookContext({
    required this.collection,
    required this.operation,
    required this.phase,
    this.record,
    this.authRecordId,
  });

  final String collection;
  final CollectionOperation operation;
  final HookPhase phase;
  final Record? record;
  final String? authRecordId;
}

/// A lifecycle extension point for collection operations.
typedef ActionHook = Future<void> Function(ActionHookContext context);
