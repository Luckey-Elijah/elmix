import 'package:elmix_engine/elmix_engine.dart';

/// Server boundary around an [ElmixEngine].
///
/// A concrete HTTP implementation can be added here without leaking transport
/// details into the Engine.
class ElmixServer {
  /// Creates a server boundary backed by [engine].
  const ElmixServer(this.engine);

  /// The engine exposed through this server boundary.
  final ElmixEngine engine;
}
