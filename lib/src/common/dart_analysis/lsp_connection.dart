import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_code_agent/src/common/dart_analysis/lsp_process.dart';
import 'package:l/l.dart';
import 'package:meta/meta.dart';

/// {@template lsp_notification}
/// A notification from the language server (`textDocument/publishDiagnostics`, `$/analyzerStatus`).
/// {@endtemplate}
@immutable
final class LspNotification {
  /// {@macro lsp_notification}
  const LspNotification(this.method, this.params);

  /// The LSP method.
  final String method;

  /// Its parameters as decoded JSON.
  final Object? params;
}

/// The server answered a request with an error.
final class LspRequestException implements Exception {
  /// Creates the exception.
  const LspRequestException(this.method, this.code, this.message);

  /// The request's method.
  final String method;

  /// The JSON-RPC error code.
  final int code;

  /// The server's message.
  final String message;

  @override
  String toString() => 'LspRequestException($method, $code: $message)';
}

/// The connection is closed: the server exited or [LspConnection.close] was called.
final class LspClosedException implements Exception {
  /// Creates the exception.
  const LspClosedException(this.method);

  /// The request that could not be answered.
  final String method;

  @override
  String toString() => 'LspClosedException($method)';
}

/// {@template lsp_connection}
/// JSON-RPC over the `Content-Length` framing of the Language Server Protocol, on an [LspProcess]:
/// requests with their answers, notifications both ways, and answers to the server's own requests.
/// {@endtemplate}
final class LspConnection {
  /// {@macro lsp_connection}
  LspConnection(this._process) {
    _subscription = _process.stdout.listen(
      _onBytes,
      onError: (Object error, StackTrace stackTrace) =>
          l.w('LSP | stdout failed: $error', stackTrace),
      onDone: _onClosed,
    );
  }

  final LspProcess _process;
  late final StreamSubscription<List<int>> _subscription;
  final StreamController<LspNotification> _notifications =
      StreamController<LspNotification>.broadcast();
  final Map<int, (String, Completer<Object?>)> _pending = <int, (String, Completer<Object?>)>{};
  final Completer<void> _done = Completer<void>();

  /// Bytes of a frame that has not fully arrived.
  Uint8List _buffer = Uint8List(0);
  int _nextId = 1;
  bool _closed = false;

  /// Answers a request of the server; by default `null`.
  FutureOr<Object?> Function(String method, Object? params) onServerRequest = _answerNull;

  static Object? _answerNull(String method, Object? params) => null;

  /// The server's notifications.
  Stream<LspNotification> get notifications => _notifications.stream;

  /// Completes when the server's stdout ends.
  Future<void> get done => _done.future;

  /// Sends the request [method] and returns its result.
  ///
  /// Throws [LspRequestException] for an error answer, [TimeoutException] after [timeout], and
  /// [LspClosedException] once the connection is closed.
  Future<Object?> request(
    String method,
    Object? params, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_closed) return Future<Object?>.error(LspClosedException(method));
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = (method, completer);
    _write(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('LSP $method', timeout);
      },
    );
  }

  /// Sends the notification [method].
  void notify(String method, Object? params) {
    if (_closed) return;
    _write(<String, Object?>{'jsonrpc': '2.0', 'method': method, 'params': ?params});
  }

  void _write(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    _process.write(<int>[...ascii.encode('Content-Length: ${body.length}\r\n\r\n'), ...body]);
  }

  void _onBytes(List<int> chunk) {
    final bytes = Uint8List(_buffer.length + chunk.length)
      ..setAll(0, _buffer)
      ..setAll(_buffer.length, chunk);
    var offset = 0;
    while (true) {
      final headerEnd = _headerEnd(bytes, offset);
      if (headerEnd < 0) break;
      final header = ascii.decode(bytes.sublist(offset, headerEnd), allowInvalid: true);
      final start = headerEnd + 4;
      final match = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false).firstMatch(header);
      if (match == null) {
        // Not a frame: skip what came before the blank line and look for the next header.
        offset = start;
        continue;
      }
      final length = int.parse(match.group(1)!);
      if (bytes.length < start + length) break;
      _onMessage(utf8.decode(bytes.sublist(start, start + length), allowMalformed: true));
      offset = start + length;
    }
    _buffer = Uint8List.fromList(bytes.sublist(offset));
  }

  /// Index of the `\r\n\r\n` that ends the header starting at [from]; `-1` when it has not arrived.
  static int _headerEnd(Uint8List bytes, int from) {
    for (var i = from; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  void _onMessage(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      l.w('LSP | not JSON: $error');
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    final id = decoded['id'];
    final method = decoded['method'];
    if (method is String && id != null) {
      _answer(id, method, decoded['params']).ignore();
    } else if (method is String) {
      if (!_notifications.isClosed) _notifications.add(LspNotification(method, decoded['params']));
    } else if (id is int) {
      final pending = _pending.remove(id);
      if (pending == null) return;
      final (requested, completer) = pending;
      if (decoded['error'] case final Map<String, Object?> error) {
        completer.completeError(
          LspRequestException(
            requested,
            (error['code'] as num?)?.toInt() ?? 0,
            '${error['message'] ?? ''}',
          ),
        );
      } else {
        completer.complete(decoded['result']);
      }
    }
  }

  Future<void> _answer(Object id, String method, Object? params) async {
    Object? result;
    try {
      result = await onServerRequest(method, params);
    } on Object catch (error, stackTrace) {
      l.w('LSP | answering $method failed: $error', stackTrace);
    }
    if (_closed) return;
    _write(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result});
  }

  void _onClosed() {
    _fail();
    if (!_done.isCompleted) _done.complete();
  }

  void _fail() {
    _closed = true;
    for (final (method, completer) in _pending.values) {
      if (!completer.isCompleted) completer.completeError(LspClosedException(method));
    }
    _pending.clear();
  }

  /// Stops reading; pending requests fail with [LspClosedException]. The process is not stopped.
  Future<void> close() async {
    _fail();
    await _subscription.cancel();
    if (!_notifications.isClosed) await _notifications.close();
    if (!_done.isCompleted) _done.complete();
  }
}
