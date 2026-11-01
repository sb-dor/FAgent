import 'dart:async';
import 'dart:convert';

import 'package:flutter_code_agent/src/common/process/grouped_process.dart';

/// {@template daemon_process}
/// A process that speaks the `flutter daemon` line protocol on stdio
/// (`flutter daemon`, `flutter run --machine`).
///
/// An interface so that tests can script the other side without a real SDK.
/// {@endtemplate}
abstract interface class DaemonProcess {
  /// Stdout, UTF-8, line by line. Lines are **not** length-limited: a response
  /// with a screenshot is a single line of several megabytes.
  Stream<String> get stdoutLines;

  /// Stderr, line by line (bounded). May be broadcast.
  Stream<String> get stderrLines;

  /// Writes [line] and a newline to stdin.
  void writeLine(String line);

  /// Exit code of the process.
  Future<int> get exitCode;

  /// Stops the whole process group.
  Future<void> stop();
}

/// Starts a [DaemonProcess]; tests substitute a scripted one.
typedef DaemonProcessStarter = Future<DaemonProcess> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// Starts [executable] as a [DaemonProcess] in its own process group
/// ([GroupedProcess]), so that [DaemonProcess.stop] also ends whatever it
/// spawned (the app being run, build tools).
Future<DaemonProcess> startGroupedDaemonProcess(
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
  return _GroupedDaemonProcess(process);
}

final class _GroupedDaemonProcess implements DaemonProcess {
  _GroupedDaemonProcess(this._process) {
    // A write to a dead process fails `done` asynchronously; the connection
    // learns about the death from `exitCode`, so this error is not interesting.
    unawaited(_process.stdin.done.then<void>((_) {}, onError: (Object _) {}));
  }

  final GroupedProcess _process;

  @override
  late final Stream<String> stdoutLines = _process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  @override
  Stream<String> get stderrLines => _process.stderrLines;

  @override
  void writeLine(String line) => _process.stdin.writeln(line);

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> stop() => _process.stop(exitAfterEof: const Duration(seconds: 2));
}
