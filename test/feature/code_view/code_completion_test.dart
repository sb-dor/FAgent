import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_workspace.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_completion_list.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/memory_code_view_state_repository.dart';
import '../../support/memory_dart_analysis_repository.dart';
import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const root = '/p';
  const main = '$root/lib/main.dart';
  const readme = '$root/README.md';
  late MemoryCodeFilesRepository files;
  late MemoryDartAnalysisRepository analysis;
  late CodeWorkspace workspace;

  DartCompletion item(
    String label, {
    DartCompletionKind kind = DartCompletionKind.classType,
    String? sort,
  }) => DartCompletion(
    label: label,
    kind: kind,
    insertText: label,
    sortText: sort,
    detail: 'detail of $label',
  );

  final answer = <DartCompletion>[
    item('String', sort: '1'),
    item('StatefulWidget', sort: '2'),
    item('StatelessWidget', sort: '3'),
    item('int', sort: '4'),
  ];

  setUp(() {
    files = MemoryCodeFilesRepository(files: <String, String>{main: '\n', readme: '\n'});
    analysis = MemoryDartAnalysisRepository(onComplete: (path, text, position) => answer);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<CodeDocument> pump(
    WidgetTester tester, {
    String path = main,
    Size size = const Size(1280, 800),
    Locale locale = const Locale('en'),
    bool dark = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    workspace = CodeWorkspace(
      projectId: 1,
      root: root,
      files: files,
      state: MemoryCodeViewStateRepository(),
      analysis: analysis,
    );
    await tester.pumpWidget(
      testApp(
        CodeView(workspace: workspace, onOpenExternally: (_) {}, listFiles: () async => <String>[]),
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
      ),
    );
    final document = (await tester.runAsync(() => workspace.tabs.open(path)))!;
    await settle(tester);
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    document.editing.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
    await tester.pump();
    return document;
  }

  void testCode(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        await tester.pump(const Duration(seconds: 1));
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  Future<void> type(WidgetTester tester, CodeDocument document, String text) async {
    document.editing.replaceSelection(text);
    await settle(tester);
  }

  Finder rows() => find.descendant(
    of: find.byType(CodeCompletionList),
    matching: find.byType(CodeCompletionRow),
  );

  List<String> labels(WidgetTester tester) =>
      tester.widgetList<CodeCompletionRow>(rows()).map((row) => row.item.label).toList();

  testCode('typing a letter opens the list with the rows of the answer', (tester) async {
    final document = await pump(tester);

    await type(tester, document, 'S');

    expect(labels(tester), <String>['String', 'StatefulWidget', 'StatelessWidget']);
    expect(find.text('detail of String'), findsOneWidget);
    expect(analysis.calls.where((call) => call.$1 == 'complete'), hasLength(1));
  });

  testCode('typing more narrows it, a name match first', (tester) async {
    final document = await pump(tester);
    await type(tester, document, 'Stat');

    expect(labels(tester), <String>['StatefulWidget', 'StatelessWidget']);

    await type(tester, document, 'el');
    expect(labels(tester), <String>['StatelessWidget']);
  });

  testCode('. opens it with everything', (tester) async {
    final document = await pump(tester);

    await type(tester, document, 'x.');

    expect(labels(tester), hasLength(4));
  });

  testCode('⌃Space opens it with nothing typed', (tester) async {
    await pump(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await settle(tester);

    expect(labels(tester), hasLength(4));
  });

  testCode('Enter inserts the highlighted row and closes the list', (tester) async {
    final document = await pump(tester);
    await type(tester, document, 'Stat');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);

    expect(document.editing.text, 'StatefulWidget\n');
    expect(rows(), findsNothing);
  });

  testCode('Tab inserts too, ↓ moves the highlight first', (tester) async {
    final document = await pump(tester);
    await type(tester, document, 'Stat');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settle(tester);

    expect(document.editing.text, 'StatelessWidget\n');
  });

  testCode('↑ wraps to the last row; Esc closes without inserting', (tester) async {
    final document = await pump(tester);
    await type(tester, document, 'S');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tester.widget<CodeCompletionRow>(rows().last).highlighted, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    expect(rows(), findsNothing);
    expect(document.editing.text, 'S\n');
  });

  testCode('stful inserts the widget with the caret on its name; typing renames State', (
    tester,
  ) async {
    analysis.onComplete = (path, text, position) => <DartCompletion>[
      const DartCompletion(
        label: 'stful',
        kind: DartCompletionKind.snippet,
        isSnippet: true,
        insertText: 'class \${1:MyWidget} extends StatefulWidget {}\n\nclass _\${1:MyWidget}State extends State<\${1:MyWidget}> {}',
      ),
    ];
    final document = await pump(tester);
    await type(tester, document, 'stful');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(document.editing.selectedText, 'MyWidget');

    await type(tester, document, 'Counter');

    expect(document.editing.text, contains('class Counter extends StatefulWidget {}'));
    expect(document.editing.text, contains('class _CounterState extends State<Counter> {}'));
  });

  testCode('a stale answer is dropped', (tester) async {
    final first = Completer<List<DartCompletion>>();
    var calls = 0;
    analysis.onComplete = (path, text, position) {
      calls++;
      return calls == 1 ? first.future : <DartCompletion>[item('Stack')];
    };
    final document = await pump(tester);
    await type(tester, document, 'S');
    await type(tester, document, 't');

    first.complete(answer);
    await settle(tester);

    expect(labels(tester), <String>['Stack']);
  });

  testCode('an empty answer opens nothing', (tester) async {
    analysis.onComplete = (path, text, position) => const <DartCompletion>[];
    final document = await pump(tester);

    await type(tester, document, 'S');

    expect(find.byType(CodeCompletionList), findsNothing);
  });

  testCode('a non-Dart file never asks', (tester) async {
    final document = await pump(tester, path: readme);

    await type(tester, document, 'S');

    expect(analysis.calls.where((call) => call.$1 == 'complete'), isEmpty);
    expect(find.byType(CodeCompletionList), findsNothing);
  });

  testCode('choosing an auto-import item adds the import', (tester) async {
    analysis
      ..onComplete = ((path, text, position) => <DartCompletion>[
        const DartCompletion(
          label: 'Uuid',
          kind: DartCompletionKind.classType,
          insertText: 'Uuid',
          data: <String, Object?>{'id': 1},
        ),
      ])
      ..onResolve = ((completion) => DartCompletion(
        label: completion.label,
        kind: completion.kind,
        insertText: completion.insertText,
        additionalEdits: const <LspTextEdit>[
          LspTextEdit(
            range: LspRange(
              start: LspPosition(line: 0, character: 0),
              end: LspPosition(line: 0, character: 0),
            ),
            newText: "import 'package:uuid/uuid.dart';\n\n",
          ),
        ],
      ));
    final document = await pump(tester);
    await type(tester, document, 'Uu');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);

    expect(document.editing.text, "import 'package:uuid/uuid.dart';\n\nUuid\n");
  });

  group('final review', () {
    testCode('C1: with a fold above, completion asks for the real line and inserts there', (tester) async {
      files.put(main, 'void a() {\n  x;\n}\nfoo\n', notify: false);
      analysis.onComplete = (path, text, position) => <DartCompletion>[
        const DartCompletion(
          label: 'fooBar',
          kind: DartCompletionKind.function,
          insertText: 'fooBar',
          edit: LspTextEdit(
            range: LspRange(
              start: LspPosition(line: 3, character: 0),
              end: LspPosition(line: 3, character: 3),
            ),
            newText: 'fooBar',
          ),
        ),
      ];
      final document = await pump(tester);
      document.editing
        ..collapseChunk(0, 3)
        ..selection = const CodeLineSelection.collapsed(index: 1, offset: 3);
      await tester.pump();
      expect(document.editing.codeLines.length, lessThan(document.editing.lineCount));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await settle(tester);
      // Every request, the first one with the block still folded too.
      expect(analysis.positions, everyElement(const LspPosition(line: 3, character: 3)));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(document.editing.text, 'void a() {\n  x;\n}\nfooBar\n');
    });

    testCode('I2: moving the caret before the request goes out asks nothing', (tester) async {
      final document = await pump(tester);
      document.editing.replaceSelection('S');
      document.editing.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      await settle(tester);

      expect(analysis.positions, isEmpty);
      expect(rows(), findsNothing);
    });

    testCode('I2: an answer that arrives after the caret moved opens nothing', (tester) async {
      final pending = Completer<List<DartCompletion>>();
      analysis.onComplete = (path, text, position) => pending.future;
      final document = await pump(tester);
      await type(tester, document, 'S');

      document.editing.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
      await tester.pump();
      pending.complete(answer);
      await settle(tester);

      expect(rows(), findsNothing);
    });

    testCode('I3: an answer in flight when a row is accepted does not reopen the list', (tester) async {
      final later = Completer<List<DartCompletion>>();
      var calls = 0;
      analysis.onComplete = (path, text, position) => ++calls == 1 ? answer : later.future;
      final document = await pump(tester);
      await type(tester, document, 'S');
      await type(tester, document, 't');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      later.complete(answer);
      await settle(tester);

      expect(rows(), findsNothing);
      expect(document.editing.text, 'String\n');
    });

    testCode('I4: clicking a row keeps the keyboard in the editor', (tester) async {
      final document = await pump(tester);
      await type(tester, document, 'Stat');

      await tester.tap(find.text('StatelessWidget'));
      await settle(tester);

      expect(document.editing.text, 'StatelessWidget\n');
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused?.findAncestorWidgetOfExactType<CodeEditor>(), isNotNull);
    });
  });

  for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
    for (final dark in const <bool>[false, true]) {
      testCode('the list fits at 900×600 in ${locale.languageCode}, ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        final document = await pump(tester, size: const Size(900, 600), locale: locale, dark: dark);

        await type(tester, document, 'S');

        expect(rows(), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
