import 'dart:async';

import 'package:flutter_code_agent/src/common/dart_analysis/lsp_connection.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/lsp_process.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:l/l.dart';
import 'package:path/path.dart' as p;

/// [DartAnalysisServer.start] was cancelled before the server answered `initialize`.
final class DartAnalysisStartCancelled implements Exception {
  /// Creates the exception.
  const DartAnalysisStartCancelled();

  @override
  String toString() => 'DartAnalysisStartCancelled';
}

/// {@template dart_analysis_server}
/// The Dart analysis server of one project over LSP (`dart language-server`): open files and
/// their text, completion, and the errors it publishes.
/// {@endtemplate}
final class DartAnalysisServer {
  DartAnalysisServer._(this._process, this._connection) {
    _connection.notifications.listen(_onNotification);
    _exited = _connection.done;
  }

  /// Starts the server for the project in [root] with the `dart` [executable] and initializes it.
  ///
  /// Throws when the process does not start or `initialize` fails or times out after
  /// [initializeTimeout]; the process is stopped then.
  static Future<DartAnalysisServer> start({
    required String executable,
    required String root,
    required Map<String, String> environment,
    LspProcessStarter starter = startGroupedLspProcess,
    Duration initializeTimeout = const Duration(seconds: 30),
    Future<void>? cancel,
  }) async {
    final process = await starter(
      executable,
      const <String>['language-server', '--protocol=lsp', '--client-id=flutter_code_agent'],
      workingDirectory: root,
      environment: environment,
    );
    final connection = LspConnection(process)..onServerRequest = _answerServer;
    final server = DartAnalysisServer._(process, connection);
    try {
      final rootUri = Uri.directory(root).toString().replaceFirst(RegExp(r'/$'), '');
      final initialize = connection.request('initialize', <String, Object?>{
        'processId': null,
        'clientInfo': <String, Object?>{'name': 'flutter_code_agent'},
        'rootUri': rootUri,
        'workspaceFolders': <Object?>[
          <String, Object?>{'uri': rootUri, 'name': p.basename(root)},
        ],
        'capabilities': <String, Object?>{
          'workspace': <String, Object?>{'configuration': true, 'workspaceFolders': true},
          'window': <String, Object?>{'workDoneProgress': false},
          'textDocument': <String, Object?>{
            'synchronization': <String, Object?>{'didSave': false},
            'completion': <String, Object?>{
              'completionItem': <String, Object?>{
                'snippetSupport': true,
                'documentationFormat': <String>['markdown', 'plaintext'],
                'resolveSupport': <String, Object?>{
                  'properties': <String>['additionalTextEdits', 'documentation'],
                },
              },
              'contextSupport': true,
            },
            'publishDiagnostics': <String, Object?>{},
          },
        },
      }, timeout: initializeTimeout);
      // Quitting while the server starts must not wait for its answer.
      await Future.any<Object?>(<Future<Object?>>[
        initialize,
        if (cancel != null) cancel.then<Object?>((_) => throw const DartAnalysisStartCancelled()),
      ]);
      connection.notify('initialized', <String, Object?>{});
    } on Object {
      await connection.close();
      await process.stop();
      rethrow;
    }
    return server;
  }

  static Object? _answerServer(String method, Object? params) => switch (method) {
    // One (empty: the defaults) settings object per asked item.
    'workspace/configuration' => <Object?>[
      for (final _
          in (params is Map ? params['items'] as List<Object?>? : null) ?? const <Object?>[])
        <String, Object?>{},
    ],
    _ => null,
  };

  final LspProcess _process;
  final LspConnection _connection;
  late final Future<void> _exited;
  final StreamController<DartFileDiagnostics> _diagnostics =
      StreamController<DartFileDiagnostics>.broadcast();
  final StreamController<bool> _analyzing = StreamController<bool>.broadcast();
  bool _disposed = false;

  /// The errors and warnings the server publishes, a file at a time.
  Stream<DartFileDiagnostics> get diagnostics => _diagnostics.stream;

  /// `true` while the server analyzes, `false` when it is done.
  Stream<bool> get analyzing => _analyzing.stream;

  /// Completes when the server's output ends (it exited or crashed).
  Future<void> get exited => _exited;

  static String _uri(String path) => Uri.file(path).toString();

  /// Tells the server [path] is open with [text].
  void open(String path, String text, int version) =>
      _connection.notify('textDocument/didOpen', <String, Object?>{
        'textDocument': <String, Object?>{
          'uri': _uri(path),
          'languageId': 'dart',
          'version': version,
          'text': text,
        },
      });

  /// Sends the whole new [text] of the open [path].
  void change(String path, String text, int version) =>
      _connection.notify('textDocument/didChange', <String, Object?>{
        'textDocument': <String, Object?>{'uri': _uri(path), 'version': version},
        'contentChanges': <Object?>[
          <String, Object?>{'text': text},
        ],
      });

  /// Tells the server [path] is no longer open (it reads the disk again).
  void close(String path) => _connection.notify('textDocument/didClose', <String, Object?>{
    'textDocument': <String, Object?>{'uri': _uri(path)},
  });

  /// The completions at [position] of the open [path].
  Future<List<DartCompletion>> complete(String path, LspPosition position) async {
    final result = await _connection.request('textDocument/completion', <String, Object?>{
      'textDocument': <String, Object?>{'uri': _uri(path)},
      'position': position.toJson(),
    });
    final items = switch (result) {
      {'items': final List<Object?> items} => items,
      final List<Object?> list => list,
      _ => const <Object?>[],
    };
    return <DartCompletion>[
      for (final item in items)
        if (item is Map<String, Object?>) DartCompletion.fromJson(item),
    ];
  }

  /// [completion] with the parts the server sends only on demand (an `import` to add).
  Future<DartCompletion> resolve(DartCompletion completion) async {
    final result = await _connection.request('completionItem/resolve', completion.toJson());
    return result is Map<String, Object?>
        ? completion.withResolved(DartCompletion.fromJson(result))
        : completion;
  }

  void _onNotification(LspNotification notification) {
    final params = notification.params;
    switch (notification.method) {
      case 'textDocument/publishDiagnostics' when params is Map:
        final uri = Uri.tryParse('${params['uri']}');
        if (uri == null || !uri.isScheme('file')) return;
        _diagnostics.add(
          DartFileDiagnostics(uri.toFilePath(), <DartDiagnostic>[
            for (final entry in (params['diagnostics'] as List<Object?>?) ?? const <Object?>[])
              if (entry is Map<String, Object?>) DartDiagnostic.fromJson(entry),
          ]),
        );
      case r'$/analyzerStatus' when params is Map:
        if (params['isAnalyzing'] case final bool analyzing) _analyzing.add(analyzing);
    }
  }

  /// Asks the server to shut down and exit, then stops its process group (within 2 s).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _connection.request('shutdown', null, timeout: const Duration(seconds: 2));
      _connection.notify('exit', null);
    } on Object catch (error) {
      l.v('Dart analysis | shutdown not answered: $error');
    }
    await _connection.close();
    await _process.stop();
    await _diagnostics.close();
    await _analyzing.close();
  }
}
