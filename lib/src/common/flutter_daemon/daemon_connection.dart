import 'dart:async';
import 'dart:convert';

import 'package:flutter_code_agent/src/common/flutter_daemon/daemon_process.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:l/l.dart';

/// {@template daemon_event}
/// An event of the daemon: `[{"event":"app.started","params":{…}}]`.
/// {@endtemplate}
final class DaemonEvent {
  /// {@macro daemon_event}
  const DaemonEvent(this.name, this.params);

  /// Event name, e.g. `daemon.connected`, `app.debugPort`.
  final String name;

  /// Event payload; empty when the daemon sent none.
  final Map<String, Object?> params;

  @override
  String toString() => 'DaemonEvent($name, $params)';
}

/// {@template daemon_connection}
/// The `flutter daemon` JSON protocol over a [DaemonProcess].
///
/// A protocol frame is a stdout line that, trimmed, starts with `[{` and ends
/// with `}]`. It holds a response (`id` + `result` / `error`) or an event.
/// Every other line — build output, "Waiting for another flutter command…",
/// a frame that is not valid JSON — is plain output and goes to [output].
///
/// [events] and [output] are broadcast: listen before the lines you need can
/// arrive (right after construction, before the first `await`).
/// {@endtemplate}
final class DaemonConnection {
  /// {@macro daemon_connection}
  DaemonConnection(this._process) {
    _stdoutSubscription = _process.stdoutLines.listen(
      _onStdoutLine,
      onError: (Object error) => l.w('DaemonConnection | stdout error: $error'),
      onDone: () {
        if (!_stdoutDone.isCompleted) _stdoutDone.complete();
      },
    );
    _stderrSubscription = _process.stderrLines.listen(
      (line) => _addOutput(line, isError: true),
      onError: (Object error) => l.w('DaemonConnection | stderr error: $error'),
      onDone: () {
        if (!_stderrDone.isCompleted) _stderrDone.complete();
      },
    );
    _done = _process.exitCode.then(_finish);
  }

  /// How long to wait, after the exit, for the rest of stdout and stderr: a
  /// leftover of the process group may keep a pipe open.
  static const Duration _drainTimeout = Duration(seconds: 1);

  final DaemonProcess _process;
  final StreamController<DaemonEvent> _events = StreamController<DaemonEvent>.broadcast();
  final StreamController<({String text, bool isError})> _output =
      StreamController<({String text, bool isError})>.broadcast();
  final Map<int, ({String method, Completer<Object?> completer})> _pending =
      <int, ({String method, Completer<Object?> completer})>{};
  final Completer<void> _stdoutDone = Completer<void>();
  final Completer<void> _stderrDone = Completer<void>();
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  late final Future<int> _done;
  Future<void>? _closing;
  int _nextId = 0;
  bool _exited = false;

  /// Events of the daemon. Broadcast; closed when the process has exited.
  Stream<DaemonEvent> get events => _events.stream;

  /// Everything the process printed outside the protocol: stdout lines with
  /// `isError` false, stderr lines with `isError` true. Broadcast.
  Stream<({String text, bool isError})> get output => _output.stream;

  /// Completes with the exit code once the process has exited, its output is
  /// handled and pending requests are failed.
  Future<int> get done => _done;

  /// Calls [method] and returns the `result` of the response.
  ///
  /// Throws [DaemonRequestException] when the response holds an `error`, and
  /// [DaemonClosedException] when the process exits before it answers.
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    if (_exited) throw DaemonClosedException(method: method);
    final id = _nextId++;
    final line = jsonEncode(<Object?>[
      <String, Object?>{'id': id, 'method': method, 'params': params},
    ]);
    final completer = Completer<Object?>();
    _pending[id] = (method: method, completer: completer);
    try {
      _process.writeLine(line);
    } on Object catch (error) {
      _pending.remove(id);
      l.w('DaemonConnection | cannot write $method: $error');
      throw DaemonClosedException(method: method);
    }
    return completer.future;
  }

  /// Stops the process (its whole group) and closes the streams.
  /// Safe to call more than once.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await _process.stop();
      await _done;
    } finally {
      await _stdoutSubscription.cancel();
      await _stderrSubscription.cancel();
    }
  }

  Future<int> _finish(int code) async {
    _exited = true;
    // The exit code can arrive before the last stdout and stderr lines (the
    // crash diagnostics) are read.
    await Future.wait<void>(<Future<void>>[
      _stdoutDone.future.timeout(_drainTimeout, onTimeout: () {}),
      _stderrDone.future.timeout(_drainTimeout, onTimeout: () {}),
    ]);
    final pending = _pending.values.toList();
    _pending.clear();
    for (final request in pending) {
      request.completer.completeError(DaemonClosedException(method: request.method));
    }
    await _events.close();
    await _output.close();
    return code;
  }

  void _addOutput(String text, {required bool isError}) {
    if (!_output.isClosed) _output.add((text: text, isError: isError));
  }

  void _onStdoutLine(String line) {
    if (!_tryHandleFrame(line)) _addOutput(line, isError: false);
  }

  bool _tryHandleFrame(String line) {
    final text = line.trim();
    if (!text.startsWith('[{') || !text.endsWith('}]')) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return false;
    }
    if (decoded is! List<Object?>) return false;
    var handled = false;
    for (final message in decoded) {
      if (message is Map<String, Object?> && _handleMessage(message)) handled = true;
    }
    return handled;
  }

  bool _handleMessage(Map<String, Object?> message) {
    final event = message['event'];
    if (event is String) {
      final params = message['params'];
      if (!_events.isClosed) {
        _events.add(
          DaemonEvent(event, params is Map<String, Object?> ? params : const <String, Object?>{}),
        );
      }
      return true;
    }
    final id = message['id'];
    if (id is int && !message.containsKey('method')) {
      final request = _pending.remove(id);
      if (request == null) {
        l.w('DaemonConnection | response to unknown request $id');
      } else if (message.containsKey('error')) {
        request.completer.completeError(
          DaemonRequestException(method: request.method, error: message['error']),
        );
      } else {
        request.completer.complete(message['result']);
      }
      return true;
    }
    return false;
  }
}
