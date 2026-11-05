import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_location.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_workspace.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_editor_view.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_references_dialog.dart';
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
  const other = '$root/lib/other.dart';
  const outside = '/sdk/lib/a.dart';
  late MemoryCodeFilesRepository files;
  late MemoryDartAnalysisRepository analysis;
  late CodeWorkspace workspace;
  late List<LspPosition> asked;

  LspLocation at(String path, int line, int start, int end) => LspLocation(
    path: path,
    range: LspRange(
      start: LspPosition(line: line, character: start),
      end: LspPosition(line: line, character: end),
    ),
  );

  setUp(() {
    files = MemoryCodeFilesRepository(
      files: <String, String>{
        main: 'void main() {\n  other();\n}\n',
        other: 'void other() {}\n',
        outside: 'class A {}\nvoid other() {}\n',
      },
    );
    asked = <LspPosition>[];
    analysis = MemoryDartAnalysisRepository()
      ..onDefinition = (path, text, position) {
        asked.add(position);
        return <LspLocation>[at(other, 0, 5, 10)];
      };
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<CodeDocument> pump(
    WidgetTester tester, {
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
    final document = (await tester.runAsync(() => workspace.tabs.open(main)))!;
    await settle(tester);
    return document;
  }

  void testCode(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        await tester.pump(const Duration(seconds: 1));
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  /// The global middle of [column] on [line] (no scroll, no fold).
  Offset charAt(WidgetTester tester, int line, int column) {
    const style = TextStyle(
      fontFamily: AppText.monoFamily,
      fontSize: CodeEditorView.fontSize,
      height: CodeEditorView.lineHeight,
    );
    final painter = TextPainter(
      text: const TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final editor = tester.getTopLeft(find.byType(CodeEditor));
    final gutter = tester.getTopRight(find.byType(DefaultCodeChunkIndicator)).dx;
    return Offset(
      gutter + CodeEditorView.padding + column * painter.width + painter.width / 2,
      editor.dy + CodeEditorView.padding + line * painter.height + painter.height / 2,
    );
  }

  /// Focuses the editor with the caret on `other` (line 1, column 3).
  Future<void> caretOnOther(WidgetTester tester) async {
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    workspace.tabs.active!.editing.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 3,
    );
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await settle(tester);
  }

  testCode('⌘-click puts the caret on the clicked name', (tester) async {
    analysis.onDefinition = null;
    final document = await pump(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    final click = await tester.startGesture(charAt(tester, 1, 4), kind: PointerDeviceKind.mouse);
    await click.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await settle(tester);

    expect(document.editing.selection.extentIndex, 1);
    expect(document.editing.selection.extentOffset, inInclusiveRange(4, 5));
  });

  testCode('F12 opens the definition with the caret on the name', (tester) async {
    await pump(tester);
    await caretOnOther(tester);

    await press(tester, LogicalKeyboardKey.f12);

    expect(asked, <LspPosition>[const LspPosition(line: 1, character: 3)]);
    expect(workspace.tabs.active?.path, other);
    expect(
      workspace.tabs.active?.editing.selection,
      const CodeLineSelection.collapsed(index: 0, offset: 5),
    );
    expect(workspace.history.canGoBack, isTrue);
  });

  testCode('⌘-click opens the definition', (tester) async {
    await pump(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    final click = await tester.startGesture(charAt(tester, 1, 4), kind: PointerDeviceKind.mouse);
    await click.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await settle(tester);

    expect(asked.single.line, 1);
    expect(workspace.tabs.active?.path, other);
  });

  testCode('a definition outside the project opens a read-only tab', (tester) async {
    analysis.onDefinition = (path, text, position) => <LspLocation>[at(outside, 1, 5, 10)];
    await pump(tester);
    await caretOnOther(tester);

    await press(tester, LogicalKeyboardKey.f12);

    expect(workspace.tabs.active?.path, outside);
    expect(workspace.tabs.active?.readOnly, isTrue);
    expect(
      workspace.tabs.active?.editing.selection,
      const CodeLineSelection.collapsed(index: 1, offset: 5),
    );
  });

  testCode('two definitions open the list; Enter opens the highlighted one', (tester) async {
    analysis.onDefinition = (path, text, position) => <LspLocation>[
      at(outside, 1, 5, 10),
      at(other, 0, 5, 10),
    ];
    await pump(tester);
    await caretOnOther(tester);

    await press(tester, LogicalKeyboardKey.f12);

    expect(find.text('Definitions of other (2)'), findsOneWidget);
    // Project files first.
    expect(
      tester.getTopLeft(find.text('lib/other.dart:1')).dy,
      lessThan(tester.getTopLeft(find.textContaining('a.dart:2')).dy),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    // The dialog's route animates out.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CodeReferencesDialog), findsNothing);
    expect(workspace.tabs.active?.path, other);
  });

  testCode('⇧F12 lists references: project files first, filter narrows, Esc closes', (
    tester,
  ) async {
    analysis.onReferences = (path, text, position) => <LspLocation>[
      at(outside, 1, 5, 10),
      at(other, 0, 5, 10),
      at(main, 1, 2, 7),
    ];
    await pump(tester);
    await caretOnOther(tester);

    await press(tester, LogicalKeyboardKey.f12, shift: true);

    expect(find.text('References to other (3)'), findsOneWidget);
    final rows = <String>['lib/main.dart:2', 'lib/other.dart:1'];
    expect(
      tester.getTopLeft(find.text(rows[0])).dy,
      lessThan(tester.getTopLeft(find.text(rows[1])).dy),
    );
    expect(find.textContaining('a.dart:2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'main.dart');
    await settle(tester);
    expect(find.text('lib/main.dart:2'), findsOneWidget);
    expect(find.text('lib/other.dart:1'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CodeReferencesDialog), findsNothing);
    expect(workspace.tabs.active?.path, main);
  });

  testCode('no definition shows the message for 2 s', (tester) async {
    analysis.onDefinition = (path, text, position) => const <LspLocation>[];
    await pump(tester);
    await caretOnOther(tester);

    await press(tester, LogicalKeyboardKey.f12);

    expect(find.text('No definition found'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2100));
    expect(find.text('No definition found'), findsNothing);
  });

  testCode('no references shows its message', (tester) async {
    await pump(tester);
    await caretOnOther(tester);

    await press(tester, LogicalKeyboardKey.f12, shift: true);

    expect(find.text('No references'), findsOneWidget);
  });

  testCode('a definition in a deleted file shows the message', (tester) async {
    analysis.onDefinition = (path, text, position) => <LspLocation>[
      at('$root/lib/gone.dart', 0, 0, 1),
    ];
    await pump(tester);
    await caretOnOther(tester);

    await press(tester, LogicalKeyboardKey.f12);

    expect(find.text('No definition found'), findsOneWidget);
    expect(workspace.tabs.active?.path, main);
  });

  testCode('a definition answer after the caret moved is dropped', (tester) async {
    final answer = Completer<List<LspLocation>>();
    analysis.onDefinition = (path, text, position) => answer.future;
    final document = await pump(tester);
    await caretOnOther(tester);
    await press(tester, LogicalKeyboardKey.f12);

    document.editing.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);
    answer.complete(<LspLocation>[at(other, 0, 5, 10)]);
    await settle(tester);

    expect(workspace.tabs.active?.path, main);
    expect(find.text('No definition found'), findsNothing);
  });

  for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
    testCode('the references dialog fits at 900×600 in ${locale.languageCode}', (tester) async {
      analysis.onReferences = (path, text, position) => <LspLocation>[
        for (var i = 0; i < 40; i++) at(other, 0, 5, 10),
        at(outside, 1, 5, 10),
      ];
      await pump(tester, size: const Size(900, 600), locale: locale);
      await caretOnOther(tester);

      await press(tester, LogicalKeyboardKey.f12, shift: true);

      expect(find.byType(CodeReferencesDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testCode('completion cannot edit a read-only tab', (tester) async {
    analysis.onComplete = (path, text, position) => const <DartCompletion>[
      DartCompletion(label: 'int', kind: DartCompletionKind.keyword, insertText: 'int'),
    ];
    await pump(tester);
    await tester.runAsync(() => workspace.tabs.open(outside));
    await settle(tester);
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);

    expect(workspace.tabs.active?.path, outside);
    expect(workspace.tabs.active?.editing.text, 'class A {}\nvoid other() {}\n');
  });

  testCode('a read-only tab shows its package label on the tab', (tester) async {
    await pump(tester);
    await tester.runAsync(() => workspace.tabs.open(outside));
    await settle(tester);

    // No package_config.json here: the label is the path.
    expect(find.text(outside), findsOneWidget);
  });

  testCode('↓ past the visible rows scrolls the highlighted one into view', (tester) async {
    analysis.onReferences = (path, text, position) => <LspLocation>[
      for (var i = 0; i < 30; i++) at('$root/lib/f${'$i'.padLeft(2, '0')}.dart', 0, 0, 1),
    ];
    await pump(tester);
    await caretOnOther(tester);
    await press(tester, LogicalKeyboardKey.f12, shift: true);

    for (var i = 0; i < 25; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await settle(tester);

    final dialog = tester.getRect(find.byType(CodeReferencesDialog));
    final row = find.text('lib/f25.dart:1');
    expect(row, findsOneWidget);
    expect(tester.getRect(row).bottom, lessThanOrEqualTo(dialog.bottom));
    expect(tester.getRect(row).top, greaterThanOrEqualTo(dialog.top));
  });
}
