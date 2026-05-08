/// Minimal command boundary for the Elmix CLI.
class ElmixCommandRunner {
  /// Creates a command runner for the Elmix CLI.
  const ElmixCommandRunner();

  /// Returns the command-line usage text.
  String usage() {
    return [
      'Elmix Core v0 CLI',
      '',
      'Commands:',
      '  elmix create <app>',
      '  elmix serve',
      '  elmix admin create',
      '  elmix schema export',
      '  elmix schema import',
    ].join('\n');
  }
}
