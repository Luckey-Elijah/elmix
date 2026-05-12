import 'dart:io';

import 'package:elmix_cli/src/command_runner.dart';

Future<void> main(List<String> args) async {
  final exitCode = await ElmixCommandRunner().run(args);
  await Future.wait<void>([stdout.close(), stderr.close()]);
  exit(exitCode);
}
