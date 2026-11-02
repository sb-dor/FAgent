import 'dart:io';

import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:path/path.dart' as p;

/// Compiles `test/support/scripted_mcp_server.dart` into [directory] and returns the path of the
/// executable. Compiling once per test file keeps each start fast while still exercising a real
/// child process.
Future<String> compileScriptedMcpServer(Directory directory) async {
  final env = await ShellEnvironment.resolve();
  final dart = env.which('dart');
  if (dart == null) throw StateError('dart is not on PATH');
  final output = p.join(directory.path, 'scripted_mcp_server');
  final result = await Process.run(dart, <String>[
    'compile',
    'exe',
    'test/support/scripted_mcp_server.dart',
    '-o',
    output,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Failed to compile the scripted MCP server:\n${result.stdout}\n${result.stderr}',
    );
  }
  return output;
}
