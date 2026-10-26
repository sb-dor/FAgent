import 'dart:io';

import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:path/path.dart' as p;

/// Compiles `test/support/fake_agent.dart` into [directory] and returns an
/// [AgentDefinition] that runs it. Compiling once per test file keeps each
/// start fast while still exercising a real child process.
Future<AgentDefinition> compileFakeAgent(
  Directory directory, {
  Map<String, String> environment = const <String, String>{},
}) async {
  final env = await ShellEnvironment.resolve();
  final dart = env.which('dart');
  if (dart == null) throw StateError('dart is not on PATH');
  final output = p.join(directory.path, 'fake_agent');
  final result = await Process.run(dart, <String>[
    'compile',
    'exe',
    'test/support/fake_agent.dart',
    '-o',
    output,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Failed to compile the fake agent:\n${result.stdout}\n${result.stderr}');
  }
  return AgentDefinition(
    id: 'fake',
    displayName: 'Fake agent',
    executable: output,
    environment: environment,
  );
}
