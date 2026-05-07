import 'package:elmix_engine/elmix_engine.dart';

/// Server boundary around an [ElmixEngine].
///
/// A concrete HTTP implementation can be added here without leaking transport
/// details into the Engine.
class ElmixServer {
  const ElmixServer(this.engine);

  final ElmixEngine engine;
}
