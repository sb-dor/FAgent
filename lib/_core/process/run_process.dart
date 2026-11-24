import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/_core/process/grouped_process.dart';

/// Runs an executable like [runProcessKillingOnTimeout] and returns its result.
typedef TimedProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  Duration? timeout,
});

/// The [ProcessRunner] of the app: the process runs in its own process group ([GroupedProcess]),
/// stdout and stderr are read as text, and when it outlives [timeout] the whole group is killed
/// (`npx` leaves `node` children behind otherwise) and a [TimeoutException] is thrown.
///
/// Whatever the group still holds after the process ends is killed too, so nothing is left running.
/// With an [environment] only that environment is passed to the process.
Future<ProcessResult> runProcessKillingOnTimeout(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  Duration? timeout,
}) async {
  final process = await GroupedProcess.start(executable, arguments, environment: environment);
  process.stdin.close().ignore();
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final stdoutSubscription = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .listen(stdout.write);
  final stderrSubscription = process.stderrLines.listen(stderr.writeln);
  try {
    final exitCode = timeout == null
        ? await process.exitCode
        : await process.exitCode.timeout(
            timeout,
            onTimeout: () => throw TimeoutException('$executable did not finish', timeout),
          );
    // A background process of the group may hold the pipes open; do not wait for it for long.
    await Future.wait<void>(<Future<void>>[
      stdoutSubscription.asFuture<void>(),
      stderrSubscription.asFuture<void>(),
    ]).timeout(const Duration(seconds: 1), onTimeout: () => const <void>[]);
    return ProcessResult(process.pgid, exitCode, stdout.toString(), stderr.toString());
  } finally {
    process.signalGroup(ProcessSignal.sigkill);
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }
}
