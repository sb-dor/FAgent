import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/dart_analysis_server.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/lsp_process.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:l/l.dart';
import 'package:path/path.dart' as p;

part 'dart_analysis_repository.freezed.dart';

/// What the Dart analysis of a project is doing.
@freezed
sealed class DartAnalysisStatus with _$DartAnalysisStatus {
  /// No Dart file was opened yet: nothing runs.
  const factory DartAnalysisStatus.idle() = DartAnalysis$IdleState;

  /// The server is starting.
  const factory DartAnalysisStatus.starting() = DartAnalysis$StartingState;

  /// The server is up and done analyzing.
  const factory DartAnalysisStatus.ready() = DartAnalysis$ReadyState;

  /// The server is analyzing.
  const factory DartAnalysisStatus.analyzing() = DartAnalysis$AnalyzingState;

  /// No analysis: `dart` is missing, or the server failed or stopped ([reason]).
  const factory DartAnalysisStatus.unavailable({required String reason}) =
      DartAnalysis$UnavailableState;
}

/// The Dart analysis of one project: the files the Code view has open, completion, and the
/// server's errors. Only `.dart` files take part.
abstract interface class IDartAnalysisRepository {
  /// [path] is open with [text]; the first Dart file starts the server.
  void open(String path, String text);

  /// The open [path] now reads [text]; sent once the edits pause.
  void change(String path, String text);

  /// [path] is closed.
  void close(String path);

  /// The completions at [position] of [path], whose text is [text] now; empty without a server.
  Future<List<DartCompletion>> complete(String path, String text, LspPosition position);

  /// [completion] with what the server sends only on demand (an `import`).
  Future<DartCompletion> resolve(DartCompletion completion);

  /// The server's errors and warnings, a file at a time.
  Stream<DartFileDiagnostics> get diagnostics;

  /// What the analysis is doing.
  ValueListenable<DartAnalysisStatus> get status;

  /// Stops the server and starts it again with the open files.
  Future<void> restart();

  /// Stops the server.
  Future<void> dispose();
}

/// [IDartAnalysisRepository] on the project's `dart language-server` (the `dart` next to the
/// project's `flutter`, fvm included).
final class DartAnalysisRepositoryImpl implements IDartAnalysisRepository {
  /// Creates the repository of the project in [root].
  DartAnalysisRepositoryImpl({
    required this._root,
    required this._environment,
    this._starter = startGroupedLspProcess,
  });

  final String _root;
  final ShellEnvironment _environment;
  final LspProcessStarter _starter;

  /// How long edits must pause before the text is sent.
  static const Duration changeDelay = Duration(milliseconds: 300);

  final ValueNotifier<DartAnalysisStatus> _status = ValueNotifier<DartAnalysisStatus>(
    const DartAnalysisStatus.idle(),
  );
  final StreamController<DartFileDiagnostics> _diagnostics =
      StreamController<DartFileDiagnostics>.broadcast();

  /// The open files: their text as the server has it, and its version.
  final Map<String, ({String text, int version})> _open = <String, ({String text, int version})>{};

  /// Text not sent yet, by file.
  final Map<String, String> _pending = <String, String>{};
  final Map<String, Timer> _timers = <String, Timer>{};

  DartAnalysisServer? _server;
  Future<void>? _starting;
  final List<StreamSubscription<Object?>> _subscriptions = <StreamSubscription<Object?>>[];
  bool _disposed = false;

  @override
  ValueListenable<DartAnalysisStatus> get status => _status;

  @override
  Stream<DartFileDiagnostics> get diagnostics => _diagnostics.stream;

  static bool _isDart(String path) => path.endsWith('.dart');

  void _setStatus(DartAnalysisStatus status) {
    if (!_disposed) _status.value = status;
  }

  @override
  void open(String path, String text) {
    if (_disposed || !_isDart(path) || _open.containsKey(path)) return;
    _open[path] = (text: text, version: 1);
    final server = _server;
    if (server != null) {
      server.open(path, text, 1);
    } else {
      _start();
    }
  }

  /// Starts the server once; the files open by then are sent when it is up.
  void _start() {
    if (_starting != null || _server != null || _disposed) return;
    if (_status.value is DartAnalysis$UnavailableState) return;
    _starting = _run().whenComplete(() => _starting = null);
  }

  Future<void> _run() async {
    final flutter = flutterExecutableFor(_root, which: _environment.which);
    if (flutter == null) {
      _setStatus(const DartAnalysisStatus.unavailable(reason: 'dart not found'));
      return;
    }
    _setStatus(const DartAnalysisStatus.starting());
    final DartAnalysisServer server;
    try {
      server = await DartAnalysisServer.start(
        executable: p.join(p.dirname(flutter), 'dart'),
        root: _root,
        environment: _environment.variables,
        starter: _starter,
      );
    } on Object catch (error, stackTrace) {
      l.w('Dart analysis | the server did not start: $error', stackTrace);
      _setStatus(DartAnalysisStatus.unavailable(reason: '$error'));
      return;
    }
    if (_disposed) {
      await server.dispose();
      return;
    }
    _server = server;
    _subscriptions
      ..add(
        server.diagnostics.listen((diagnostics) {
          if (!_diagnostics.isClosed) _diagnostics.add(diagnostics);
        }),
      )
      ..add(
        server.analyzing.listen(
          (analyzing) => _setStatus(
            analyzing ? const DartAnalysisStatus.analyzing() : const DartAnalysisStatus.ready(),
          ),
        ),
      );
    _setStatus(const DartAnalysisStatus.ready());
    for (final MapEntry(key: path, value: file) in _open.entries) {
      server.open(path, file.text, file.version);
    }
    unawaited(
      server.exited.then((_) {
        if (_disposed || !identical(_server, server)) return;
        _forget();
        _setStatus(const DartAnalysisStatus.unavailable(reason: 'the server stopped'));
      }),
    );
  }

  @override
  void change(String path, String text) {
    if (!_open.containsKey(path)) return;
    _pending[path] = text;
    _timers[path]?.cancel();
    _timers[path] = Timer(changeDelay, () => _flush(path));
  }

  /// Sends the pending text of [path] (or [text] when it differs from what the server has).
  void _flush(String path, [String? text]) {
    _timers.remove(path)?.cancel();
    final pending = text ?? _pending.remove(path);
    _pending.remove(path);
    final file = _open[path];
    if (pending == null || file == null || pending == file.text) return;
    final version = file.version + 1;
    _open[path] = (text: pending, version: version);
    _server?.change(path, pending, version);
  }

  @override
  void close(String path) {
    _timers.remove(path)?.cancel();
    _pending.remove(path);
    if (_open.remove(path) != null) _server?.close(path);
  }

  @override
  Future<List<DartCompletion>> complete(String path, String text, LspPosition position) async {
    final server = _server;
    if (server == null || !_open.containsKey(path)) return const <DartCompletion>[];
    _flush(path, text);
    try {
      return await server.complete(path, position);
    } on Object catch (error) {
      l.v('Dart analysis | completion failed: $error');
      return const <DartCompletion>[];
    }
  }

  @override
  Future<DartCompletion> resolve(DartCompletion completion) async {
    final server = _server;
    if (server == null || completion.data == null) return completion;
    try {
      return await server.resolve(completion);
    } on Object catch (error) {
      l.v('Dart analysis | resolve failed: $error');
      return completion;
    }
  }

  /// Drops the current server without stopping it (it is gone or being stopped).
  void _forget() {
    for (final subscription in _subscriptions) {
      subscription.cancel().ignore();
    }
    _subscriptions.clear();
    _server = null;
  }

  @override
  Future<void> restart() async {
    final server = _server;
    _forget();
    await server?.dispose();
    await _starting;
    if (_disposed) return;
    _setStatus(const DartAnalysisStatus.idle());
    // The server lost what it had: every open file is sent again at version 1.
    for (final path in _open.keys.toList()) {
      final text = _pending.remove(path) ?? _open[path]!.text;
      _timers.remove(path)?.cancel();
      _open[path] = (text: text, version: 1);
    }
    if (_open.isNotEmpty) {
      _start();
      await _starting;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    await _starting;
    final server = _server;
    _forget();
    await server?.dispose();
    await _diagnostics.close();
    _status.dispose();
  }
}
