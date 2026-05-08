import 'dart:io';

import 'package:elmix_cli/elmix_cli.dart';

void main(List<String> arguments) {
  const runner = ElmixCommandRunner();
  stdout.writeln(runner.usage());
}
