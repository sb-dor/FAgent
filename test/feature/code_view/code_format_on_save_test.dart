import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_workspace.dart';
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
  const unformatted = 'void  main( ){}\n';
  const formatted = 'void main() {}\n';
  late MemoryCodeFilesRepository files;
  late MemoryDartAnalysisRepository analysis;
  late CodeWorkspace workspace;
  late bool formatOnSave;

  LspTextEdit edit(int start, int end, String text) => LspTextEdit(
    range: LspRange(
      start: LspPosition(line: 0, character: start),
      end: LspPosition(line: 0, character: end),
    ),
    newText: text,
  );

  /// The edits for a text that starts with [unformatted]; nothing for any other text.
  List<LspTextEdit>? edits(String text) => text.startsWith(unformatted)
      ? <LspTextEdit>[edit(4, 5, ''), edit(11, 12, ''), edit(13, 13, ' ')]
      : const <LspTextEdit>[];

  setUp(() {
    files = MemoryCodeFilesRepository(files: <String, String>{main: unformatted});
    analysis = MemoryDartAnalysisRepository()..onFormat = (path, text) => edits(text);
    formatOnSave = true;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<CodeDocument> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    workspace = CodeWorkspace(
      projectId: 1,
      root: root,
      files: files,
      state: MemoryCodeViewStateRepository(),
      analysis: analysis,
      formatOnSave: () => formatOnSave,
    );
    await tester.pumpWidget(
      testApp(
        CodeView(workspace: workspace, onOpenExternally: (_) {}, listFiles: () async => <String>[]),
      ),
    );
    final document = (await tester.runAsync(() => workspace.tabs.open(main)))!;
    await settle(tester);
    await tester.tap(find.byType(CodeEditor));
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

  Future<void> save(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await settle(tester);
  }

  /// Puts a change in the document so it has something to save.
  void dirty(CodeDocument document) {
    document.editing
      ..selection = const CodeLineSelection.collapsed(index: 1, offset: 0)
      ..replaceSelection('\n');
  }

  testCode('⌘S formats then saves', (tester) async {
    final document = await pump(tester);
    dirty(document);

    await save(tester);

    expect(files.files[main], startsWith(formatted));
    expect(document.dirty, isFalse);
    expect(document.editing.text, startsWith(formatted));
  });

  testCode('⌘Z after ⌘S brings back the unformatted text', (tester) async {
    final document = await pump(tester);
    dirty(document);
    await save(tester);

    document.editing.undo();

    expect(document.editing.text, startsWith(unformatted));
  });

  testCode('with the setting off ⌘S saves unformatted', (tester) async {
    formatOnSave = false;
    final document = await pump(tester);
    dirty(document);

    await save(tester);

    expect(files.files[main], startsWith(unformatted));
  });

  testCode('a null format answer (syntax error) saves as is', (tester) async {
    analysis.onFormat = (path, text) => null;
    final document = await pump(tester);
    dirty(document);

    await save(tester);

    expect(files.files[main], startsWith(unformatted));
    expect(document.dirty, isFalse);
  });

  testCode('typing during the format request saves the typed text unformatted', (tester) async {
    final answer = Completer<List<LspTextEdit>?>();
    analysis.onFormat = (path, text) => answer.future;
    final document = await pump(tester);
    dirty(document);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();
    document.editing
      ..selection = const CodeLineSelection.collapsed(index: 0, offset: 0)
      ..replaceSelection('// ');
    answer.complete(edits(unformatted));
    await settle(tester);

    expect(files.files[main], document.editing.text);
    expect(files.files[main], startsWith('// $unformatted'));
  });

  testCode('⇧⌥F formats without saving', (tester) async {
    final document = await pump(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await settle(tester);

    expect(document.editing.text, formatted);
    expect(document.dirty, isTrue);
    expect(files.files[main], unformatted);
  });

  testCode('save all formats Dart tabs', (tester) async {
    final document = await pump(tester);
    dirty(document);

    await tester.runAsync(workspace.tabs.saveAll);
    await settle(tester);

    expect(files.files[main], startsWith(formatted));
  });
}
