import 'package:elmix_engine/elmix_engine.dart';

/// Boundary for the Admin Control Plane.
class AdminControlPlane {
  /// Creates an admin control plane backed by [engine].
  const AdminControlPlane(this.engine);

  /// The engine managed by this admin boundary.
  final ElmixEngine engine;
}
