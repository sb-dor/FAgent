import 'dart:async';
import 'dart:convert';

import 'package:flutter_code_agent/src/common/dart_analysis/lsp_process.dart';

/// An [LspProcess] whose server side is played by the test.
///
/// [send] frames a message to the client; every message the client writes is decoded into
/// [received] and handed to [onMessage], which may answer it.
final class ScriptedLspProcess implements LspProcess {
  /// Creates the process.
  ScriptedLspProcess({this.onMessage});

  /// Answers a client message; `null` to stay silent.
  FutureOr<void> Function(ScriptedLspProcess process, Map<String, Object?> message)? onMessage;

  /// The client's messages in order.
  final List<Map<String, Object?>> received = <Map<String, Object?>>[];

  /// The client's messages as written, header and all.
  final List<List<int>> writes = <List<int>>[];

  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();
  final List<int> _buffer = <int>[];

  /// Whether [stop] was called.
  bool stopped = false;

  /// Frames [message] as the server's stdout.
  void send(Map<String, Object?> message) => sendRaw(frame(message));

  /// Puts [bytes] on stdout as they are.
  void sendRaw(List<int> bytes) {
    if (!_stdout.isClosed) _stdout.add(bytes);
  }

  /// The bytes of [message] with its `Content-Length` header.
  static List<int> frame(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    return <int>[...ascii.encode('Content-Length: ${body.length}\r\n\r\n'), ...body];
  }

  /// Answers the request [message] with [result].
  void reply(Map<String, Object?> message, Object? result) =>
      send(<String, Object?>{'jsonrpc': '2.0', 'id': message['id'], 'result': result});

  /// Ends the process with [code].
  Future<void> exit([int code = 0]) async {
    if (!_stdout.isClosed) await _stdout.close();
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  void write(List<int> bytes) {
    writes.add(bytes);
    _buffer.addAll(bytes);
    while (true) {
      final header = _indexOf(_buffer, const <int>[13, 10, 13, 10]);
      if (header < 0) return;
      final length = int.parse(
        RegExp(r'Content-Length: (\d+)')
            .firstMatch(ascii.decode(_buffer.sublist(0, header)))!
            .group(1)!,
      );
      final start = header + 4;
      if (_buffer.length < start + length) return;
      final message =
          jsonDecode(utf8.decode(_buffer.sublist(start, start + length))) as Map<String, Object?>;
      _buffer.removeRange(0, start + length);
      received.add(message);
      onMessage?.call(this, message);
    }
  }

  static int _indexOf(List<int> bytes, List<int> needle) {
    outer:
    for (var i = 0; i <= bytes.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<void> stop() async {
    stopped = true;
    await exit(-15);
  }
}
