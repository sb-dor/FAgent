import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/dart_analysis/lsp_process.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/dart_analysis_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/scripted_lsp_process.dart';

void main() {
  late io.Directory sdk;
  late String root;
  late String file;
  late List<ScriptedLspProcess> processes;

  setUp(() {
    // A fake Flutter SDK whose bin holds `flutter` (found on PATH) and `dart` next to it.
    sdk = io.Directory.systemTemp.createTempSync('fake_sdk');
    io.File(p.join(sdk.path, 'bin', 'flutter')).createSync(recursive: true);
    root = io.Directory.systemTemp.createTempSync('analysis_project').path;
    file = p.join(root, 'lib', 'main.dart');
    processes = <ScriptedLspProcess>[];
    addTearDown(() {
      sdk.deleteSync(recursive: true);
      io.Directory(root).deleteSync(recursive: true);
    });
  });

  ScriptedLspProcess server() => ScriptedLspProcess(
    onMessage: (process, message) {
      if (!message.containsKey('id')) return;
      switch (message['method']) {
        case 'initialize':
          process.reply(message, <String, Object?>{'capabilities': {}});
        case 'shutdown':
          process.reply(message, null);
        case 'textDocument/completion':
          process.reply(message, <Object?>[
            <String, Object?>{'label': 'int', 'kind': 7},
          ]);
      }
    },
  );

  LspProcessStarter starter() => (executable, arguments, {workingDirectory, environment}) async {
    expect(executable, p.join(sdk.path, 'bin', 'dart'));
    final process = server();
    processes.add(process);
    return process;
  };

  DartAnalysisRepositoryImpl create({String? path}) {
    final repository = DartAnalysisRepositoryImpl(
      root: root,
      environment: ShellEnvironment(<String, String>{'PATH': path ?? p.join(sdk.path, 'bin')}),
      starter: starter(),
    );
    addTearDown(repository.dispose);
    return repository;
  }

  Future<void> settle([int ms = 10]) => Future<void>.delayed(Duration(milliseconds: ms));

  List<String> methods(ScriptedLspProcess process) => <String>[
    for (final message in process.received)
      if (message['method'] case final String method) method,
  ];

  test('a non-Dart file starts nothing', () async {
    final repository = create()..open(p.join(root, 'pubspec.yaml'), 'name: app');
    await settle();

    expect(processes, isEmpty);
    expect(repository.status.value, const DartAnalysisStatus.idle());
  });

  test('the first Dart open starts the server: starting, then ready', () async {
    final repository = create();
    final statuses = <DartAnalysisStatus>[];
    repository.status.addListener(() => statuses.add(repository.status.value));

    repository.open(file, 'void main() {}');
    await settle();

    expect(statuses, <DartAnalysisStatus>[
      const DartAnalysisStatus.starting(),
      const DartAnalysisStatus.ready(),
    ]);
    expect(
      methods(processes.single),
      containsAllInOrder(<String>['initialize', 'initialized', 'textDocument/didOpen']),
    );
  });

  test('changes within 300 ms send one didChange with the latest text and version', () async {
    final repository = create()..open(file, 'a');
    await settle();

    repository
      ..change(file, 'ab')
      ..change(file, 'abc');
    await settle(350);

    final changes = processes.single.received.where((m) => m['method'] == 'textDocument/didChange');
    expect(changes, hasLength(1));
    final params = changes.single['params']! as Map<String, Object?>;
    expect((params['textDocument']! as Map)['version'], 2);
    expect((params['contentChanges']! as List).single, <String, Object?>{'text': 'abc'});
  });

  test('complete flushes the pending change before asking', () async {
    final repository = create()..open(file, 'i');
    await settle();
    repository.change(file, 'in');

    final items = await repository.complete(file, 'in', const LspPosition(line: 0, character: 2));

    expect(items.single.label, 'int');
    final order = methods(processes.single);
    expect(
      order.lastIndexOf('textDocument/didChange'),
      lessThan(order.lastIndexOf('textDocument/completion')),
    );
    await settle(350);
    expect(order.where((m) => m == 'textDocument/didChange'), hasLength(1));
  });

  test('complete sends text that differs from what the server has', () async {
    final repository = create()..open(file, 'i');
    await settle();

    await repository.complete(file, 'int x', const LspPosition(line: 0, character: 5));

    final change = processes.single.received.lastWhere(
      (m) => m['method'] == 'textDocument/didChange',
    );
    expect(((change['params']! as Map)['contentChanges'] as List).single, <String, Object?>{
      'text': 'int x',
    });
  });

  test('diagnostics pass through', () async {
    final repository = create()..open(file, 'x');
    await settle();
    final received = <DartFileDiagnostics>[];
    repository.diagnostics.listen(received.add);

    processes.single.send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': 'textDocument/publishDiagnostics',
      'params': <String, Object?>{'uri': Uri.file(file).toString(), 'diagnostics': <Object?>[]},
    });
    await settle();

    expect(received.single.path, file);
  });

  test('analyzing true and false map to analyzing and ready', () async {
    final repository = create()..open(file, 'x');
    await settle();

    processes.single.send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': r'$/analyzerStatus',
      'params': <String, Object?>{'isAnalyzing': true},
    });
    await settle();
    expect(repository.status.value, const DartAnalysisStatus.analyzing());

    processes.single.send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': r'$/analyzerStatus',
      'params': <String, Object?>{'isAnalyzing': false},
    });
    await settle();
    expect(repository.status.value, const DartAnalysisStatus.ready());
  });

  test('no flutter on PATH is unavailable("dart not found")', () async {
    final repository = create(path: '/nowhere')..open(file, 'x');
    await settle();

    expect(repository.status.value, const DartAnalysisStatus.unavailable(reason: 'dart not found'));
    expect(processes, isEmpty);
    expect(await repository.complete(file, 'x', const LspPosition(line: 0, character: 1)), isEmpty);
  });

  test(
    'the server exiting is unavailable; restart starts it again and re-opens the open files',
    () async {
      final repository = create()..open(file, 'void main() {}');
      await settle();

      await processes.single.exit(1);
      await settle();
      expect(repository.status.value, isA<DartAnalysis$UnavailableState>());

      await repository.restart();
      await settle();

      expect(processes, hasLength(2));
      expect(repository.status.value, const DartAnalysisStatus.ready());
      final reopened = processes.last.received.singleWhere(
        (m) => m['method'] == 'textDocument/didOpen',
      );
      expect(((reopened['params']! as Map)['textDocument'] as Map)['text'], 'void main() {}');
    },
  );

  test('close sends didClose and stops tracking the file', () async {
    final repository = create()..open(file, 'x');
    await settle();

    repository
      ..change(file, 'xy')
      ..close(file);
    await settle(350);

    expect(methods(processes.single), contains('textDocument/didClose'));
    expect(methods(processes.single), isNot(contains('textDocument/didChange')));
  });

  test('I1: dispose during a start that hangs stops it at once', () async {
    final hung = ScriptedLspProcess();
    final repository = DartAnalysisRepositoryImpl(
      root: root,
      environment: ShellEnvironment(<String, String>{'PATH': p.join(sdk.path, 'bin')}),
      starter: (executable, arguments, {workingDirectory, environment}) async => hung,
    )..open(file, 'x');
    await settle();
    expect(repository.status.value, const DartAnalysisStatus.starting());

    await repository.dispose().timeout(const Duration(seconds: 2));

    expect(hung.stopped, isTrue);
  });

  test('dispose stops the server', () async {
    final repository = create()..open(file, 'x');
    await settle();

    await repository.dispose();

    expect(processes.single.stopped, isTrue);
    expect(methods(processes.single), containsAllInOrder(<String>['shutdown', 'exit']));
  });
}
