// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';

/// {@template agent_preflight_exception}
/// The agent cannot start on this machine; [message] says why and [hint] how
/// to fix it.
/// {@endtemplate}
final class AgentPreflightException implements Exception {
  /// {@macro agent_preflight_exception}
  const AgentPreflightException(this.message, {this.hint});

  /// What is wrong.
  final String message;

  /// Command or action that fixes it.
  final String? hint;

  @override
  String toString() => 'AgentPreflightException: $message';
}

/// Checks that an agent can be started before spawning it.
abstract final class AgentPreflight {
  /// Returns the absolute path of the agent executable.
  ///
  /// Throws [AgentPreflightException] when the executable is missing or the
  /// installed Node.js is older than [AgentDefinition.minimumNodeMajor].
  static Future<String> check(
    AgentDefinition definition,
    ShellEnvironment environment, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final minimumNode = definition.minimumNodeMajor;
    if (minimumNode != null) {
      final node = environment.which('node');
      if (node == null) {
        throw AgentPreflightException(
          'Node.js $minimumNode+ is required for ${definition.displayName} but was not found.',
          hint: 'Install Node.js $minimumNode or newer (https://nodejs.org)',
        );
      }
      final major = await _nodeMajor(node, environment, timeout);
      if (major == null || major < minimumNode) {
        throw AgentPreflightException(
          'Node.js $minimumNode+ is required for ${definition.displayName}, '
          'found ${major ?? 'an unknown version'}.',
          hint: 'Install Node.js $minimumNode or newer (https://nodejs.org)',
        );
      }
    }
    final executable = definition.executable.startsWith('/')
        ? definition.executable
        : environment.which(definition.executable);
    if (executable == null || !io.FileSystemEntity.isFileSync(executable)) {
      throw AgentPreflightException(
        '`${definition.executable}` was not found on PATH.',
        hint: environment.isFallback
            ? 'Could not read your shell environment; check that your shell starts quickly.'
            : null,
      );
    }
    return executable;
  }

  static Future<int?> _nodeMajor(String node, ShellEnvironment env, Duration timeout) async {
    final result = await io.Process.run(
      node,
      const <String>['--version'],
      environment: env.variables,
      includeParentEnvironment: false,
    ).timeout(timeout);
    final match = RegExp(r'^v(\d+)\.').firstMatch('${result.stdout}'.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
