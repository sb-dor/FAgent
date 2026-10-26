import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/process/bounded_line_splitter.dart';
import 'package:l/l.dart';

/// {@template grouped_process}
/// A child process started in its own process group, so that stopping it also
/// stops everything it spawned — including background processes that were
/// re-parented to `launchd` (`dev-server &`).
///
/// Dart cannot `setpgid` a child, so the command runs as a background job of
/// `/bin/sh` with job control on (`set -m`): every job gets a new process group.
/// stdio passes through unchanged, and the shell exits with the job's status.
/// {@endtemplate}
final class GroupedProcess {
  GroupedProcess._(this._process, this.pgid, this.stderrLines);

  static const String _pgidMarker = '__FLUTTER_CODE_AGENT_PGID__';

  // "$0" "$@" keep every argument intact: nothing is re-parsed by the shell.
  // `set +m` right after the fork: the job already has its own group, and job
  // control off keeps "[1]+ Done" notifications out of the child's stderr.
  // `wait … 2>/dev/null` hides the shell's own "Terminated: 15" report; the
  // job's stderr is a separate descriptor and is not affected.
  static const String _script =
      r'set -m; "$0" "$@" & pid=$!; set +m; echo "__FLUTTER_CODE_AGENT_PGID__ $pid" >&2; '
      r'wait $pid 2>/dev/null';

  /// Starts [executable] with [arguments] in a new process group.
  ///
  /// [stderrLines] gets the child's stderr through [BoundedLineSplitter].
  static Future<GroupedProcess> start(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
    int maxStderrLineBytes = 2000,
    Duration startTimeout = const Duration(seconds: 10),
  }) async {
    final process = await io.Process.start(
      '/bin/sh',
      <String>['-c', _script, executable, ...arguments],
      environment: environment,
      includeParentEnvironment: environment == null,
      workingDirectory: workingDirectory,
    );
    final pgid = Completer<int>();
    final stderr = StreamController<String>.broadcast(sync: true);
    process.stderr
        .transform(BoundedLineSplitter(maxLineBytes: maxStderrLineBytes))
        .listen(
          (line) {
            if (!pgid.isCompleted && line.startsWith(_pgidMarker)) {
              final id = int.tryParse(line.substring(_pgidMarker.length).trim());
              if (id != null) return pgid.complete(id);
            }
            stderr.add(line);
          },
          onDone: () {
            if (!pgid.isCompleted)
              pgid.completeError(StateError('Process exited before reporting its group'));
            stderr.close();
          },
        );
    try {
      return GroupedProcess._(process, await pgid.future.timeout(startTimeout), stderr.stream);
    } on Object {
      process.kill(io.ProcessSignal.sigkill);
      rethrow;
    }
  }

  final io.Process _process;

  /// Process group id of the job (equals its pid).
  final int pgid;

  /// Child stderr, line by line (bounded, ANSI-stripped). Broadcast.
  final Stream<String> stderrLines;

  /// The child's stdin.
  io.IOSink get stdin => _process.stdin;

  /// The child's stdout, unchanged.
  Stream<List<int>> get stdout => _process.stdout;

  /// Exit code of the job.
  Future<int> get exitCode => _process.exitCode;

  /// Sends [signal] to every process in the group. Returns `false` when the
  /// group no longer exists.
  bool signalGroup(io.ProcessSignal signal) => io.Process.killPid(-pgid, signal);

  /// Stops the job and everything in its group.
  ///
  /// Closes stdin and waits up to [gracePeriod] for a clean exit, then sends
  /// SIGTERM to the group and SIGKILL after another [gracePeriod]. The group
  /// is signalled even after a clean exit: background processes the job left
  /// behind are still members.
  Future<void> stop({Duration gracePeriod = const Duration(seconds: 5)}) async {
    try {
      await _process.stdin.close();
    } on Object catch (error) {
      l.v('GroupedProcess | stdin already closed: $error');
    }
    final exited = await _waitForExit(gracePeriod);
    if (!signalGroup(io.ProcessSignal.sigterm)) {
      if (!exited) _process.kill(io.ProcessSignal.sigkill);
      return;
    }
    await _waitForExit(gracePeriod);
    if (signalGroup(io.ProcessSignal.sigkill)) {
      l.w('GroupedProcess | group $pgid ignored SIGTERM, sent SIGKILL');
    }
    await _waitForExit(gracePeriod);
  }

  Future<bool> _waitForExit(Duration timeout) =>
      _process.exitCode.then((_) => true).timeout(timeout, onTimeout: () => false);
}
