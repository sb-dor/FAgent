import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_workspace.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_tab_bar.dart';
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
  const pubspec = '$root/pubspec.yaml';
  late MemoryCodeFilesRepository files;
  late CodeWorkspace workspace;
  late List<String> external;

  setUp(() {
    files = MemoryCodeFilesRepository(
      files: <String, String>{
        main: 'void main() {\n  runApp();\n}\n',
        pubspec: 'name: p\n',
        '$root/logo.png': '',
        '$root/app.bin': '',
      },
      notText: <String>{'$root/app.bin'},
    );
    external = <String>[];
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    List<String> open = const <String>[main],
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
    );
    await tester.pumpWidget(
      testApp(
        CodeView(
          workspace: workspace,
          onOpenExternally: external.add,
          listFiles: () async => <String>['lib/main.dart', 'lib/src/domain.dart', 'pubspec.yaml'],
        ),
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
      ),
    );
    for (final path in open) {
      await tester.runAsync(() => workspace.tabs.open(path));
    }
    await settle(tester);
  }

  /// [testWidgets] on macOS that ends by unmounting the view and closing the workspace, so its timers end
  /// inside the test.
  void testCode(String description, Future<void> Function(WidgetTester tester) body) => testWidgets(
    description,
    (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      workspace.dispose();
      await tester.pump(const Duration(seconds: 1));
    },
    // The app's platform: the editor's keys and cursor behave as on a Mac.
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  CodeDocument document(String path) => workspace.tabs.tabs.firstWhere((tab) => tab.path == path);

  /// Focuses the editor; the tap puts the caret where it lands, so it goes back to the start.
  Future<void> focusEditor(WidgetTester tester) async {
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    workspace.tabs.active?.editing.selection = const CodeLineSelection.zero();
  }

  Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await settle(tester);
  }

  testCode('a tab shows the file name and the editor its text', (tester) async {
    await pump(tester);

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.byTooltip('lib/main.dart'), findsOneWidget);
  });

  testCode('typing marks the tab ●, ⌘S clears it and writes the file', (tester) async {
    await pump(tester);
    await focusEditor(tester);

    document(main).editing.replaceSelection('// x\n');
    await tester.pump();
    expect(find.text('●'), findsOneWidget);

    await shortcut(tester, LogicalKeyboardKey.keyS);

    expect(find.text('●'), findsNothing);
    expect(files.files[main], startsWith('// x\n'));
  });

  testCode('⌘S on a stale file asks, Overwrite writes, Cancel keeps it dirty', (tester) async {
    await pump(tester);
    await focusEditor(tester);
    document(main).editing.replaceSelection('mine ');
    files.put(main, 'theirs\n', notify: false);

    await shortcut(tester, LogicalKeyboardKey.keyS);
    expect(find.text('The file changed on disk. Overwrite it?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(document(main).dirty, isTrue);
    expect(files.files[main], 'theirs\n');

    await focusEditor(tester);
    await shortcut(tester, LogicalKeyboardKey.keyS);
    await tester.tap(find.text('Overwrite'));
    await settle(tester);
    expect(document(main).dirty, isFalse);
    expect(files.files[main], startsWith('mine '));
  });

  group('⌘W on a dirty tab asks', () {
    for (final (answer, closed, written) in <(String, bool, bool)>[
      ('Save', true, true),
      ("Don't save", true, false),
      ('Cancel', false, false),
    ]) {
      testCode(answer, (tester) async {
        await pump(tester);
        await focusEditor(tester);
        document(main).editing.replaceSelection('x');

        await shortcut(tester, LogicalKeyboardKey.keyW);
        expect(find.text('Save changes to main.dart?'), findsOneWidget);
        await tester.tap(find.text(answer));
        await settle(tester);

        expect(workspace.tabs.tabs.isEmpty, closed);
        expect(files.files[main]!.startsWith('x'), written);
      });
    }
  });

  testCode('⌘W closes a clean tab without asking', (tester) async {
    await pump(tester);
    await focusEditor(tester);

    await shortcut(tester, LogicalKeyboardKey.keyW);

    expect(workspace.tabs.tabs, isEmpty);
    expect(find.text('Choose a file on the left or press ⌘P'), findsOneWidget);
  });

  testCode('middle click closes a clean tab', (tester) async {
    await pump(tester, open: <String>[main, pubspec]);

    await tester.tap(
      find.descendant(of: find.byType(CodeTabBar), matching: find.text('pubspec.yaml')),
      buttons: kMiddleMouseButton,
    );
    await settle(tester);

    expect(workspace.tabs.tabs.map((tab) => tab.path), <String>[main]);
  });

  testCode('clicking a tab activates it', (tester) async {
    await pump(tester, open: <String>[main, pubspec]);

    await tester.tap(find.text('main.dart'));
    await settle(tester);

    expect(workspace.tabs.active?.path, main);
  });

  testCode('the conflict bar reloads from disk', (tester) async {
    await pump(tester);
    document(main).editing.replaceSelection('mine ');
    files.put(main, 'theirs\n');
    await settle(tester);

    expect(find.text('The file changed on disk'), findsOneWidget);
    await tester.tap(find.text('Load from disk'));
    await settle(tester);

    expect(document(main).editing.text, 'theirs\n');
    expect(find.text('The file changed on disk'), findsNothing);
  });

  testCode('the conflict bar keeps mine', (tester) async {
    await pump(tester);
    document(main).editing.replaceSelection('mine ');
    files.put(main, 'theirs\n');
    await settle(tester);

    await tester.tap(find.text('Keep mine'));
    await settle(tester);

    expect(document(main).editing.text, startsWith('mine '));
    expect(find.text('The file changed on disk'), findsNothing);
  });

  testCode('a deleted file shows Deleted and ⌘S recreates it', (tester) async {
    await pump(tester);
    files.remove(main);
    await settle(tester);
    expect(find.text('Deleted'), findsOneWidget);

    await focusEditor(tester);
    await shortcut(tester, LogicalKeyboardKey.keyS);

    expect(files.files[main], 'void main() {\n  runApp();\n}\n');
    expect(find.text('Deleted'), findsNothing);
  });

  testCode('an image shows a picture', (tester) async {
    await pump(tester, open: <String>['$root/logo.png']);

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CodeEditor), findsNothing);
  });

  testCode('a binary shows the line and the external button', (tester) async {
    await pump(tester, open: <String>['$root/app.bin']);

    expect(find.text("Can't open in the editor"), findsOneWidget);
    await tester.tap(find.text('Open in default app'));
    await settle(tester);

    expect(external, <String>['$root/app.bin']);
  });

  testCode('⌘P finds lib/main.dart by "main" and opens it', (tester) async {
    await pump(tester, open: <String>[pubspec]);
    await focusEditor(tester);

    await shortcut(tester, LogicalKeyboardKey.keyP);
    await tester.enterText(find.byType(TextField), 'main');
    await settle(tester);

    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('lib/src/domain.dart'), findsOneWidget);
    // A basename match ranks above a path match.
    expect(
      tester.getTopLeft(find.text('lib/main.dart')).dy,
      lessThan(tester.getTopLeft(find.text('lib/src/domain.dart')).dy),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(workspace.tabs.active?.path, main);
  });

  testCode('Esc with find open closes find and stays in Code', (tester) async {
    await pump(tester);
    await focusEditor(tester);

    await shortcut(tester, LogicalKeyboardKey.keyF);
    expect(find.byKey(const ValueKey<String>('code-find-panel')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    expect(find.byKey(const ValueKey<String>('code-find-panel')), findsNothing);
    expect(find.byType(CodeView), findsOneWidget);
  });

  testCode('switching tabs keeps the caret and undo of each', (tester) async {
    await pump(tester, open: <String>[main, pubspec]);
    final first = document(main);
    first.editing
      ..selection = const CodeLineSelection.collapsed(index: 1, offset: 2)
      ..replaceSelection('x');

    workspace.tabs.activate(pubspec);
    await settle(tester);
    workspace.tabs.activate(main);
    await settle(tester);

    expect(identical(document(main), first), isTrue);
    expect(first.editing.selection, const CodeLineSelection.collapsed(index: 1, offset: 3));
    expect(first.editing.canUndo, isTrue);
  });

  for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
    for (final dark in const <bool>[false, true]) {
      testCode('the editor does not overflow at 900×600 in ${locale.languageCode}, '
          '${dark ? 'dark' : 'light'}', (tester) async {
        await pump(
          tester,
          open: <String>[main, pubspec, '$root/app.bin'],
          size: const Size(900, 600),
          locale: locale,
          dark: dark,
        );
        document(pubspec).editing.replaceSelection('x');
        files.put(pubspec, 'theirs\n');
        await settle(tester);
        workspace.tabs.activate(pubspec);
        await settle(tester);

        expect(tester.takeException(), isNull);
      });
    }
  }
}
