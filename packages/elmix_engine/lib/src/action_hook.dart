import 'package:elmix_engine/src/access_rule.dart';
import 'package:elmix_engine/src/auth.dart';
import 'package:elmix_engine/src/record.dart';

/// Whether an [ActionHook] runs before or after the operation.
enum HookPhase {
  /// Runs the hook before the operation.
  before,

  /// Runs the hook after the operation.
  after,
}

/// An authentication action that can run lifecycle hooks.
enum AuthenticationOperation {
  /// Authenticates an application record.
  authenticate,
}

/// Context passed to collection lifecycle hooks.
class ActionHookContext {
  /// Creates context for a collection lifecycle hook.
  const ActionHookContext({
    required this.collection,
    required this.operation,
    required this.phase,
    this.record,
    this.authRecord,
  });

  /// The collection associated with the hook.
  final String collection;

  /// The collection operation being performed.
  final CollectionOperation operation;

  /// Whether the hook runs before or after the operation.
  final HookPhase phase;

  /// The record associated with the operation, when available.
  final Record? record;

  /// The authenticated record identity associated with the operation.
  final AuthRecordIdentity? authRecord;
}

/// A lifecycle extension point for collection operations.
// ignore: one_member_abstracts
abstract class ActionHook {
  /// Runs this hook for [context].
  Future<void> call(ActionHookContext context);
}

/// Context passed to authentication lifecycle hooks.
class AuthenticationActionHookContext {
  /// Creates context for an authentication lifecycle hook.
  const AuthenticationActionHookContext({
    required this.collection,
    required this.action,
    required this.phase,
    this.authRecord,
  });

  /// The Auth Collection associated with the authentication action.
  final String collection;

  /// The authentication action being performed.
  final AuthenticationOperation action;

  /// Whether the hook runs before or after the action.
  final HookPhase phase;

  /// The authenticated record identity, when available.
  final AuthRecordIdentity? authRecord;
}

/// A lifecycle extension point for authentication operations.
// ignore: one_member_abstracts
abstract class AuthenticationActionHook {
  /// Runs this hook for [context].
  Future<void> call(AuthenticationActionHookContext context);
}
