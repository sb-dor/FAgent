import 'dart:async';
import 'dart:convert';

import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_process.dart';

/// A [DaemonProcess] whose other side is driven by the test.
///
/// [emit] and friends play the daemon; every request the code under test
/// writes lands in [sent] (and in [onRequest], for automatic answers).
final class ScriptedDaemonProcess implements DaemonProcess {
  /// Creates a scripted process; [arguments] and friends are filled in by
  /// [scriptedStarter] and may be set by hand when it is not used.
  ScriptedDaemonProcess({
    this.executable = 'flutter',
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment,
  });

  /// Executable the process was "started" with.
  String executable;

  /// Arguments the process was "started" with.
  List<String> arguments;

  /// Working directory the process was "started" with.
  String? workingDirectory;

  /// Environment the process was "started" with.
  Map<String, String>? environment;

  /// Requests written by the code under test, parsed (`{"id":…,"method":…}`).
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];

  /// Lines written to stdin that are not protocol frames.
  final List<String> rawLinesSent = <String>[];

  /// Called synchronously for every request written; answer with [respond].
  void Function(Map<String, Object?> request)? onRequest;

  /// Whether [stop] was called.
  bool stopped = false;

  final StreamController<String> _stdout = StreamController<String>();
  final StreamController<String> _stderr = StreamController<String>.broadcast();
  final Completer<int> _exit = Completer<int>();

  @override
  Stream<String> get stdoutLines => _stdout.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void writeLine(String line) {
    if (_exit.isCompleted) throw StateError('Process already exited');
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      decoded = null;
    }
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      final request = Map<String, Object?>.from(decoded.first as Map);
      sent.add(request);
      onRequest?.call(request);
    } else {
      rawLinesSent.add(line);
    }
  }

  /// Writes the protocol frame `[<frame>]` to stdout.
  void emit(Map<String, Object?> frame) => emitLine(jsonEncode(<Object?>[frame]));

  /// Writes [line] to stdout as is.
  void emitLine(String line) {
    if (!_stdout.isClosed) _stdout.add(line);
  }

  /// Writes [line] to stderr.
  void emitError(String line) {
    if (!_stderr.isClosed) _stderr.add(line);
  }

  /// Answers request [id] with [result], or with [error] when it is not null.
  void respond(int id, {Object? result, Object? error}) =>
      emit(<String, Object?>{'id': id, if (error != null) 'error': error else 'result': result});

  /// Ends the process with [code] and, unless [closePipes] is false, closes
  /// both output streams. With `closePipes: false` the pipes stay open for
  /// [emitLine] / [emitError] (the exit code can arrive before the pipes are
  /// drained) until [closePipes] is called.
  void exit(int code, {bool closePipes = true}) {
    if (_exit.isCompleted) return;
    _exit.complete(code);
    if (closePipes) this.closePipes();
  }

  /// Closes stdout and stderr.
  void closePipes() {
    closeStdout();
    unawaited(_stderr.close());
  }

  /// Closes stdout only; stderr stays open for [emitError].
  void closeStdout() => unawaited(_stdout.close());

  @override
  Future<void> stop() async {
    stopped = true;
    exit(0);
  }
}

/// A [DaemonProcessStarter] that hands out [create]d scripted processes,
/// recording how each was started and adding it to [started].
DaemonProcessStarter scriptedStarter(
  ScriptedDaemonProcess Function() create, {
  List<ScriptedDaemonProcess>? started,
}) => (executable, arguments, {workingDirectory, environment}) async {
  final process = create()
    ..executable = executable
    ..arguments = arguments
    ..workingDirectory = workingDirectory
    ..environment = environment;
  started?.add(process);
  return process;
};
