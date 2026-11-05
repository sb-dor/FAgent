import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/lsp_range.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_workspace.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/memory_code_view_state_repository.dart';
import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const root = '/p';
  const main = '$root/lib/main.dart';
  const other = '$root/lib/other.dart';
  late MemoryCodeFilesRepository files;
  late CodeWorkspace workspace;

  setUp(() {
    files = MemoryCodeFilesRepository(
      files: <String, String>{main: 'void main() {\n  other();\n}\n', other: 'void other() {}\n'},
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    workspace = CodeWorkspace(
      projectId: 1,
      root: root,
      files: files,
      state: MemoryCodeViewStateRepository(),
    );
    await tester.pumpWidget(
      testApp(
        CodeView(
          workspace: workspace,
          onOpenExternally: (_) {},
          listFiles: () async => <String>['lib/main.dart', 'lib/other.dart'],
        ),
      ),
    );
    await tester.runAsync(() => workspace.tabs.open(main));
    await settle(tester);
  }

  void testCode(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        workspace.dispose();
        await tester.pump(const Duration(seconds: 1));
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  Future<void> focusAt(WidgetTester tester, CodeLineSelection selection) async {
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    workspace.tabs.active!.editing.selection = selection;
    await tester.pump();
  }

  Future<void> keys(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await settle(tester);
  }

  testCode('⌘P records the place it leaves; ⌃- and ⌃⇧- go back and forward', (tester) async {
    await pump(tester);
    await focusAt(tester, const CodeLineSelection.collapsed(index: 1, offset: 4));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'other');
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(workspace.tabs.active?.path, other);
    expect(workspace.history.canGoBack, isTrue);

    await keys(tester, LogicalKeyboardKey.minus);
    expect(workspace.tabs.active?.path, main);
    expect(
      workspace.tabs.active?.editing.selection,
      const CodeLineSelection.collapsed(index: 1, offset: 4),
    );

    await keys(tester, LogicalKeyboardKey.minus, shift: true);
    expect(workspace.tabs.active?.path, other);
  });

  testCode('the back button is disabled without history and goes back with it', (tester) async {
    await pump(tester);
    IconButton back() => tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(IconButton)),
    );
    IconButton forward() => tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.arrow_forward), matching: find.byType(IconButton)),
    );
    expect(back().onPressed, isNull);
    expect(forward().onPressed, isNull);
    expect(find.byTooltip('Back (⌃-)'), findsOneWidget);
    expect(find.byTooltip('Forward (⌃⇧-)'), findsOneWidget);

    await tester.runAsync(
      () => workspace.navigateTo(other, at: const LspPosition(line: 0, character: 5)),
    );
    await settle(tester);
    expect(back().onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);
    expect(workspace.tabs.active?.path, main);
    expect(forward().onPressed, isNotNull);
  });

  testCode('a place whose file was deleted is skipped', (tester) async {
    const gone = '$root/lib/gone.dart';
    files.put(gone, 'x\n', notify: false);
    await pump(tester);
    await tester.runAsync(() => workspace.navigateTo(gone));
    await tester.runAsync(() => workspace.navigateTo(other));
    workspace.tabs.close(gone);
    files.files.remove(gone);
    await settle(tester);

    await tester.runAsync(workspace.goBack);
    await settle(tester);
    // gone.dart is skipped: back lands on main.dart.
    expect(workspace.tabs.active?.path, main);
  });
}
