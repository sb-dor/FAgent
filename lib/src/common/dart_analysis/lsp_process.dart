import 'dart:async';

import 'package:flutter_code_agent/src/common/process/grouped_process.dart';

/// {@template lsp_process}
/// A process that speaks the Language Server Protocol on stdio (`dart language-server`).
///
/// An interface so that tests can play the server without a real SDK.
/// {@endtemplate}
abstract interface class LspProcess {
  /// Stdout as it arrives: framed LSP messages, split anywhere.
  Stream<List<int>> get stdout;

  /// Writes [bytes] to stdin.
  void write(List<int> bytes);

  /// Exit code of the process.
  Future<int> get exitCode;

  /// Stops the whole process group.
  Future<void> stop();
}

/// Starts an [LspProcess]; tests substitute a scripted one.
typedef LspProcessStarter = Future<LspProcess> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// Starts [executable] as an [LspProcess] in its own process group ([GroupedProcess]), so that
/// [LspProcess.stop] ends whatever it spawned too.
Future<LspProcess> startGroupedLspProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final process = await GroupedProcess.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  return _GroupedLspProcess(process);
}

final class _GroupedLspProcess implements LspProcess {
  _GroupedLspProcess(this._process) {
    // A write to a dead process fails `done` asynchronously; the connection learns about the death
    // from the end of stdout, so this error is not interesting.
    unawaited(_process.stdin.done.then<void>((_) {}, onError: (Object _) {}));
  }

  final GroupedProcess _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  void write(List<int> bytes) => _process.stdin.add(bytes);

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> stop() => _process.stop(exitAfterEof: const Duration(seconds: 2));
}
