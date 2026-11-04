import 'dart:async';

import 'package:flutter_code_agent/src/common/dart_analysis/dart_analysis_server.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/lsp_process.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_lsp_process.dart';

void main() {
  const root = '/work/app';
  const file = '/work/app/lib/main.dart';
  const uri = 'file:///work/app/lib/main.dart';
  late ScriptedLspProcess process;
  late List<(String, List<String>, String?)> starts;

  /// The server answers `initialize`, `shutdown` and whatever [answers] has for a method.
  ScriptedLspProcess server({
    bool answersInitialize = true,
    bool answersShutdown = true,
    Map<String, Object? Function(Map<String, Object?> params)> answers =
        const <String, Object? Function(Map<String, Object?>)>{},
  }) => ScriptedLspProcess(
    onMessage: (process, message) {
      final method = message['method'];
      if (!message.containsKey('id')) return;
      if (method == 'initialize') {
        if (answersInitialize) process.reply(message, <String, Object?>{'capabilities': {}});
      } else if (method == 'shutdown') {
        if (answersShutdown) process.reply(message, null);
      } else if (answers[method] case final answer?) {
        process.reply(
          message,
          answer((message['params'] ?? <String, Object?>{}) as Map<String, Object?>),
        );
      }
    },
  );

  LspProcessStarter starter() => (executable, arguments, {workingDirectory, environment}) async {
    starts.add((executable, arguments, workingDirectory));
    return process;
  };

  Future<DartAnalysisServer> start({Duration initializeTimeout = const Duration(seconds: 30)}) =>
      DartAnalysisServer.start(
        executable: '/sdk/bin/dart',
        root: root,
        environment: const <String, String>{'PATH': '/usr/bin'},
        starter: starter(),
        initializeTimeout: initializeTimeout,
      );

  Map<String, Object?> sent(String method) =>
      process.received.lastWhere((message) => message['method'] == method);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() => starts = <(String, List<String>, String?)>[]);

  test('start sends initialize with snippet and resolve support, then initialized', () async {
    process = server();

    final analysis = await start();
    addTearDown(analysis.dispose);

    final (executable, arguments, workingDirectory) = starts.single;
    expect(executable, '/sdk/bin/dart');
    expect(arguments, <String>[
      'language-server',
      '--protocol=lsp',
      '--client-id=flutter_code_agent',
    ]);
    expect(workingDirectory, root);
    final params = sent('initialize')['params']! as Map<String, Object?>;
    expect(params['rootUri'], 'file:///work/app');
    expect(params['workspaceFolders'], <Object?>[
      <String, Object?>{'uri': 'file:///work/app', 'name': 'app'},
    ]);
    final item =
        ((params['capabilities']! as Map)['textDocument'] as Map)['completion']['completionItem']
            as Map;
    expect(item['snippetSupport'], isTrue);
    expect((item['resolveSupport'] as Map)['properties'], contains('additionalTextEdits'));
    expect(process.received.map((message) => message['method']), contains('initialized'));
  });

  test('start fails and stops the process when initialize does not answer in time', () async {
    process = server(answersInitialize: false);

    await expectLater(
      start(initializeTimeout: const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
    expect(process.stopped, isTrue);
  });

  test('open, change and close send the text with versions', () async {
    process = server();
    final analysis = await start();
    addTearDown(analysis.dispose);

    analysis
      ..open(file, 'void main() {}', 1)
      ..change(file, 'void main() { }', 2)
      ..close(file);
    await settle();

    expect(sent('textDocument/didOpen')['params'], <String, Object?>{
      'textDocument': <String, Object?>{
        'uri': uri,
        'languageId': 'dart',
        'version': 1,
        'text': 'void main() {}',
      },
    });
    expect(sent('textDocument/didChange')['params'], <String, Object?>{
      'textDocument': <String, Object?>{'uri': uri, 'version': 2},
      'contentChanges': <Object?>[
        <String, Object?>{'text': 'void main() { }'},
      ],
    });
    expect(sent('textDocument/didClose')['params'], <String, Object?>{
      'textDocument': <String, Object?>{'uri': uri},
    });
  });

  group('complete', () {
    const range = <String, Object?>{
      'start': <String, Object?>{'line': 0, 'character': 0},
      'end': <String, Object?>{'line': 0, 'character': 3},
    };

    test(
      'parses a CompletionList: label, kind, detail, snippet, textEdit, additional edits',
      () async {
        process = server(
          answers: <String, Object? Function(Map<String, Object?>)>{
            'textDocument/completion': (params) => <String, Object?>{
              'isIncomplete': false,
              'items': <Object?>[
                <String, Object?>{
                  'label': 'stful',
                  'kind': 15,
                  'detail': 'Insert a StatefulWidget',
                  'insertTextFormat': 2,
                  'textEdit': <String, Object?>{
                    'range': range,
                    'newText': r'class ${1:MyWidget} {}',
                  },
                },
                <String, Object?>{
                  'label': 'Uuid',
                  'kind': 7,
                  'filterText': 'Uuid',
                  'sortText': '001',
                  'additionalTextEdits': <Object?>[
                    <String, Object?>{
                      'range': <String, Object?>{
                        'start': <String, Object?>{'line': 0, 'character': 0},
                        'end': <String, Object?>{'line': 0, 'character': 0},
                      },
                      'newText': "import 'package:uuid/uuid.dart';\n",
                    },
                  ],
                  'data': <String, Object?>{'id': 4},
                },
              ],
            },
          },
        );
        final analysis = await start();
        addTearDown(analysis.dispose);

        final items = await analysis.complete(file, const LspPosition(line: 0, character: 3));

        final params = sent('textDocument/completion')['params']! as Map<String, Object?>;
        expect(params['position'], <String, Object?>{'line': 0, 'character': 3});
        expect((params['textDocument']! as Map)['uri'], uri);
        final stful = items.first;
        expect(stful.label, 'stful');
        expect(stful.kind, DartCompletionKind.snippet);
        expect(stful.detail, 'Insert a StatefulWidget');
        expect(stful.isSnippet, isTrue);
        expect(stful.insertText, r'class ${1:MyWidget} {}');
        expect(
          stful.edit,
          const LspTextEdit(
            range: LspRange(
              start: LspPosition(line: 0, character: 0),
              end: LspPosition(line: 0, character: 3),
            ),
            newText: r'class ${1:MyWidget} {}',
          ),
        );
        final uuid = items.last;
        expect(uuid.kind, DartCompletionKind.classType);
        expect(uuid.isSnippet, isFalse);
        expect(uuid.insertText, 'Uuid');
        expect(uuid.sortText, '001');
        expect(uuid.additionalEdits.single.newText, "import 'package:uuid/uuid.dart';\n");
        expect(uuid.data, <String, Object?>{'id': 4});
      },
    );

    test('accepts a plain array', () async {
      process = server(
        answers: <String, Object? Function(Map<String, Object?>)>{
          'textDocument/completion': (params) => <Object?>[
            <String, Object?>{'label': 'int', 'kind': 7},
          ],
        },
      );
      final analysis = await start();
      addTearDown(analysis.dispose);

      final items = await analysis.complete(file, const LspPosition(line: 0, character: 1));

      expect(items.single.label, 'int');
      expect(items.single.filterText, 'int');
    });

    test('resolve fills additionalEdits', () async {
      process = server(
        answers: <String, Object? Function(Map<String, Object?>)>{
          'completionItem/resolve': (params) => <String, Object?>{
            ...params,
            'additionalTextEdits': <Object?>[
              <String, Object?>{'range': range, 'newText': 'import x;\n'},
            ],
          },
        },
      );
      final analysis = await start();
      addTearDown(analysis.dispose);

      final resolved = await analysis.resolve(
        const DartCompletion(
          label: 'X',
          kind: DartCompletionKind.classType,
          insertText: 'X',
          data: <String, Object?>{'id': 1},
        ),
      );

      expect((sent('completionItem/resolve')['params']! as Map)['data'], <String, Object?>{
        'id': 1,
      });
      expect(resolved.additionalEdits.single.newText, 'import x;\n');
      expect(resolved.label, 'X');
    });
  });

  test('publishDiagnostics becomes DartFileDiagnostics with severities', () async {
    process = server();
    final analysis = await start();
    addTearDown(analysis.dispose);
    final received = <DartFileDiagnostics>[];
    analysis.diagnostics.listen(received.add);

    process.send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': 'textDocument/publishDiagnostics',
      'params': <String, Object?>{
        'uri': uri,
        'diagnostics': <Object?>[
          for (final (severity, code) in <(int, Object)>[
            (1, 'undefined_identifier'),
            (2, 7),
            (4, 'x'),
          ])
            <String, Object?>{
              'range': <String, Object?>{
                'start': <String, Object?>{'line': 1, 'character': 2},
                'end': <String, Object?>{'line': 1, 'character': 3},
              },
              'severity': severity,
              'message': 'm$severity',
              'code': code,
            },
        ],
      },
    });
    await settle();

    expect(received.single.path, file);
    expect(received.single.diagnostics.map((d) => d.severity), <DartSeverity>[
      DartSeverity.error,
      DartSeverity.warning,
      DartSeverity.hint,
    ]);
    expect(received.single.diagnostics.first.code, 'undefined_identifier');
    expect(received.single.diagnostics[1].code, '7');
    expect(received.single.diagnostics.first.message, 'm1');
    expect(received.single.diagnostics.first.range.start, const LspPosition(line: 1, character: 2));
  });

  test(r'$/analyzerStatus true and false is analyzing', () async {
    process = server();
    final analysis = await start();
    addTearDown(analysis.dispose);
    final analyzing = <bool>[];
    analysis.analyzing.listen(analyzing.add);

    for (final value in <bool>[true, false]) {
      process.send(<String, Object?>{
        'jsonrpc': '2.0',
        'method': r'$/analyzerStatus',
        'params': <String, Object?>{'isAnalyzing': value},
      });
    }
    await settle();

    expect(analyzing, <bool>[true, false]);
  });

  test('workspace/configuration is answered with an item per request item', () async {
    process = server();
    final analysis = await start();
    addTearDown(analysis.dispose);

    process.send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 99,
      'method': 'workspace/configuration',
      'params': <String, Object?>{
        'items': <Object?>[
          <String, Object?>{'section': 'dart'},
        ],
      },
    });
    await settle();
    await settle();

    expect(process.received.lastWhere((message) => message['id'] == 99)['result'], <Object?>[
      <String, Object?>{},
    ]);
  });

  test('dispose sends shutdown and exit and stops the process', () async {
    process = server();
    final analysis = await start();

    await analysis.dispose();

    expect(
      process.received.map((message) => message['method']),
      containsAllInOrder(<String>['shutdown', 'exit']),
    );
    expect(process.stopped, isTrue);
  });

  test('dispose stops a server that ignores shutdown within 2 s', () async {
    process = server(answersShutdown: false);
    final analysis = await start();

    await analysis.dispose().timeout(const Duration(seconds: 4));

    expect(process.stopped, isTrue);
  });

  test('exited completes when the process ends', () async {
    process = server();
    final analysis = await start();
    addTearDown(analysis.dispose);

    await process.exit(1);

    await analysis.exited.timeout(const Duration(seconds: 1));
  });
}
