import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_preflight.dart';
import 'package:flutter_code_agent/src/common/process/bounded_line_splitter.dart';
import 'package:flutter_code_agent/src/common/process/grouped_process.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';

/// {@template agent_login}
/// One running login of an agent: its output and result.
/// {@endtemplate}
final class AgentLogin {
  AgentLogin._(this.agentId, this.methodId);

  /// Agent being logged in.
  final String agentId;

  /// Login method (`claude-ai-login`, `console-login`).
  final String methodId;

  final RingBuffer<String> _output = RingBuffer<String>(500);

  /// Output lines so far (bounded, ANSI-stripped). Notifies on every line.
  final ValueNotifier<List<String>> output = ValueNotifier<List<String>>(const <String>[]);

  final Completer<bool> _done = Completer<bool>();

  /// `true` when the login command exited with code 0.
  Future<bool> get succeeded => _done.future;

  void _line(String line) {
    _output.add(line);
    output.value = _output.items;
  }
}

/// {@template agent_auth}
/// Runs agent login commands; at most one per agent at a time.
///
/// Login belongs to the agent, not to a chat: every chat of the agent waits
/// on the same [AgentLogin].
/// {@endtemplate}
final class AgentAuth {
  /// {@macro agent_auth}
  AgentAuth({required this._environment});

  final ShellEnvironment _environment;
  bool _disposed = false;
  final Map<String, (AgentLogin, GroupedProcess?)> _running =
      <String, (AgentLogin, GroupedProcess?)>{};

  /// Login in progress for [agentId], if any.
  AgentLogin? current(String agentId) => _running[agentId]?.$1;

  /// Whether any login is running.
  bool get isRunning => _running.isNotEmpty;

  /// Starts [methodId] for [definition], or returns the login already running.
  AgentLogin login(AgentDefinition definition, String methodId) {
    final running = _running[definition.id];
    if (running != null) return running.$1;
    final extra = definition.loginArguments[methodId];
    if (extra == null) throw ArgumentError.value(methodId, 'methodId', 'unknown login method');
    final login = AgentLogin._(definition.id, methodId);
    _running[definition.id] = (login, null);
    unawaited(_run(definition, extra, login));
    return login;
  }

  Future<void> _run(AgentDefinition definition, List<String> extra, AgentLogin login) async {
    var ok = false;
    try {
      final executable = await AgentPreflight.check(definition, _environment);
      final process = await GroupedProcess.start(
        executable,
        <String>[...definition.arguments, ...extra],
        environment: <String, String>{..._environment.variables, ...definition.environment},
      );
      _running[definition.id] = (login, process);
      if (_disposed) {
        // dispose ran while the preflight check was still in progress.
        await process.stop(exitAfterEof: Duration.zero, gracePeriod: const Duration(seconds: 2));
      }
      process.stderrLines.listen(login._line);
      unawaited(process.stdout.transform(const BoundedLineSplitter()).forEach(login._line));
      ok = await process.exitCode == 0;
    } on AgentPreflightException catch (error) {
      login._line(error.message);
    } on Object catch (error) {
      login._line('Login failed: $error');
    } finally {
      _running.remove(definition.id);
      login._done.complete(ok);
    }
  }

  /// Stops every running login (and any that is still starting).
  Future<void> dispose() {
    _disposed = true;
    return Future.wait<void>(<Future<void>>[
      for (final (_, process) in List<(AgentLogin, GroupedProcess?)>.of(_running.values))
        if (process != null)
          process.stop(exitAfterEof: Duration.zero, gracePeriod: const Duration(seconds: 2)),
    ]);
  }
}
