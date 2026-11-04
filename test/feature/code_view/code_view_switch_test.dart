import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_view_state.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_explorer.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_view.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/prompt_composer.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/memory_code_view_state_repository.dart';
import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late MemoryCodeViewStateRepository state;
  late List<int> projects;
  late int session;

  setUp(() {
    state = MemoryCodeViewStateRepository();
    dependencies = testDependencies(
      codeFilesRepository: MemoryCodeFilesRepository(
        files: <String, String>{'/p/lib/main.dart': 'void main() {}\n', '/q/README.md': '# q\n'},
      ),
      codeViewStateRepository: state,
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<WorkspaceConfigWidgetState> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    Locale locale = const Locale('en'),
    bool dark = false,
    bool selectProject = true,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    (projects, session) = (await tester.runAsync(() async {
      final database = dependencies.database;
      final ids = <int>[
        for (final path in <String>['/p', '/q'])
          await database
              .into(database.projectsTable)
              .insert(ProjectsTableCompanion.insert(path: path, name: path.substring(1))),
      ];
      final chat = await database
          .into(database.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: ids.first,
              agentId: 'claude',
              title: const Value<String>('First chat'),
            ),
          );
      return (ids, chat);
    }))!;
    await tester.pumpWidget(
      testApp(
        const WorkspaceConfigWidget(),
        dependencies: dependencies,
        withSettings: true,
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
      ),
    );
    await settle(tester);
    final workspace = WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));
    if (selectProject) {
      workspace.dataController
        ..selectProject(projects.first)
        ..selectSession(session);
      await settle(tester);
    }
    return workspace;
  }

  Finder segment(String label) => find.descendant(
    of: find.byKey(const ValueKey<String>('code-view-switch')),
    matching: find.text(label),
  );

  testWidgets('no project, no switch', (tester) async {
    await pump(tester, selectProject: false);

    expect(find.byKey(const ValueKey<String>('code-view-switch')), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('Code shows the explorer and the empty hint, Chat brings the same chat back', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(EditableText).last, 'my draft');

    await tester.tap(segment('Code'));
    await settle(tester);

    expect(find.byType(CodeExplorer), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('Choose a file on the left or press ⌘P'), findsOneWidget);
    expect(find.byType(PromptComposer), findsNothing);

    await tester.tap(segment('Chat'));
    await settle(tester);

    expect(find.byType(CodeView), findsNothing);
    expect(find.text('my draft'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the mode is per project and remembered', (tester) async {
    final workspace = await pump(tester);

    await tester.tap(segment('Code'));
    await settle(tester);
    workspace.dataController.selectProject(projects.last);
    await settle(tester);

    expect(find.byType(CodeExplorer), findsNothing);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    expect(state.states[projects.first]?.mode, CodeViewMode.code);

    workspace.dataController.selectProject(projects.first);
    await settle(tester);
    expect(find.byType(CodeExplorer), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('clicking a file opens a tab', (tester) async {
    final workspace = await pump(tester);
    await tester.tap(segment('Code'));
    await settle(tester);

    await tester.tap(find.text('lib'));
    await settle(tester);
    await tester.tap(find.text('main.dart'));
    await settle(tester);

    expect(workspace.codeWorkspace?.tabs.active?.path, '/p/lib/main.dart');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the divider drags the explorer width within 180–480', (tester) async {
    final workspace = await pump(tester);
    await tester.tap(segment('Code'));
    await settle(tester);
    final divider = find.byKey(const ValueKey<String>('code-explorer-divider'));

    await tester.drag(divider, const Offset(100, 0));
    await settle(tester);
    expect(workspace.codeWorkspace?.tabs.explorerWidth, 340);
    expect(tester.getSize(find.byType(CodeExplorer)).width, 340);

    await tester.drag(divider, const Offset(-400, 0));
    await settle(tester);
    expect(workspace.codeWorkspace?.tabs.explorerWidth, 180);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('⌘K still opens chat search with the editor focused', (tester) async {
    final workspace = await pump(tester);
    await tester.tap(segment('Code'));
    await settle(tester);
    await tester.runAsync(() => workspace.codeWorkspace!.tabs.open('/p/lib/main.dart'));
    await settle(tester);
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await settle(tester);

    expect(find.text('Search chats…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await disposeTestApp(tester, dependencies);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
    for (final dark in const <bool>[false, true]) {
      testWidgets('the Code view does not overflow at 900×600 in ${locale.languageCode}, '
          '${dark ? 'dark' : 'light'}', (tester) async {
        await pump(tester, size: const Size(900, 600), locale: locale, dark: dark);

        await tester.tap(segment(locale.languageCode == 'ru' ? 'Код' : 'Code'));
        await settle(tester);

        expect(find.byType(CodeExplorer), findsOneWidget);
        expect(tester.takeException(), isNull);
        await disposeTestApp(tester, dependencies);
      });
    }
  }
}
