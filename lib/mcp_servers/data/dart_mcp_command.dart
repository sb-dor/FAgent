import 'package:path/path.dart' as p;

/// The command that starts Dart MCP on the Flutter SDK in [sdkRoot]: the same one every agent
/// session gets and the status probe runs.
///
/// Its `launch_app` and `stop_app` tools are off, so every run belongs to the Run tab.
({String command, List<String> args}) dartMcpCommand(String sdkRoot) => (
  command: p.join(sdkRoot, 'bin', 'dart'),
  args: <String>['mcp-server', '--flutter-sdk', sdkRoot, '--disable', 'launch_app,stop_app'],
);
