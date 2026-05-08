import 'package:elmix_engine/src/access_rule.dart';
import 'package:elmix_engine/src/record.dart';

/// Whether an [ActionHook] runs before or after the operation.
enum HookPhase {
  /// Runs the hook before the operation.
  before,

  /// Runs the hook after the operation.
  after,
}

/// Context passed to collection lifecycle hooks.
class ActionHookContext {
  /// Creates context for a collection lifecycle hook.
  const ActionHookContext({
    required this.collection,
    required this.operation,
    required this.phase,
    this.record,
    this.authRecordId,
  });

  /// The collection associated with the hook.
  final String collection;

  /// The collection operation being performed.
  final CollectionOperation operation;

  /// Whether the hook runs before or after the operation.
  final HookPhase phase;

  /// The record associated with the operation, when available.
  final Record? record;

  /// The authenticated record ID associated with the operation, when available.
  final String? authRecordId;
}

/// A lifecycle extension point for collection operations.
typedef ActionHook = Future<void> Function(ActionHookContext context);
