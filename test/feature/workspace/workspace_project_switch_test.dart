import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_view_state.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_explorer.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_tab_bar.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/prompt_composer.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/memory_code_view_state_repository.dart';
import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late MemoryCodeViewStateRepository state;
  late int first;
  late int second;
  late int firstChat;
  late int secondOld;
  late int secondNew;

  setUp(() {
    state = MemoryCodeViewStateRepository();
    dependencies = testDependencies(
      codeFilesRepository: MemoryCodeFilesRepository(
        files: <String, String>{'/p/lib/main.dart': 'p\n', '/q/README.md': 'q\n'},
      ),
      codeViewStateRepository: state,
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<WorkspaceConfigWidgetState> pump(WidgetTester tester) async {
    useDesktopView(tester);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final db = dependencies.database;
      first = await db
          .into(db.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/p', name: 'alpha'));
      second = await db
          .into(db.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/q', name: 'beta'));
      firstChat = await db
          .into(db.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: first,
              agentId: 'claude',
              title: const Value<String>('alpha chat'),
            ),
          );
      secondOld = await db
          .into(db.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: second,
              agentId: 'claude',
              title: const Value<String>('beta old'),
              updatedAt: Value<DateTime>(DateTime(2026, 11, 1)),
            ),
          );
      secondNew = await db
          .into(db.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: second,
              agentId: 'claude',
              title: const Value<String>('beta new'),
              updatedAt: Value<DateTime>(DateTime(2026, 11, 3)),
            ),
          );
    });
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    final workspace = WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));
    workspace.dataController
      ..selectProject(first)
      ..selectSession(firstChat);
    await settle(tester);
    return workspace;
  }

  Future<void> code(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('code-view-switch')),
        matching: find.text('Code'),
      ),
    );
    await settle(tester);
  }

  Finder inExplorer(String name) =>
      find.descendant(of: find.byType(CodeExplorer), matching: find.text(name));

  Finder tab(String name) => find.descendant(of: find.byType(CodeTabBar), matching: find.text(name));

  testWidgets('in Code, a chat of another project shows its files and its own tabs; the first '
      "project's tabs come back on return", (tester) async {
    final workspace = await pump(tester);
    await code(tester);
    await tester.runAsync(() => workspace.codeWorkspace!.tabs.open('/p/lib/main.dart'));
    await settle(tester);
    expect(tab('main.dart'), findsOneWidget);

    await tester.tap(find.text('beta new'));
    await settle(tester);

    expect(workspace.dataController.projectId, second);
    expect(find.byType(CodeExplorer), findsOneWidget);
    expect(inExplorer('README.md'), findsOneWidget);
    expect(tab('main.dart'), findsNothing);

    await tester.tap(find.text('alpha chat'));
    await settle(tester);
    expect(tab('main.dart'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('in Chat, a chat of another project stays in Chat even if it was left in Code', (
    tester,
  ) async {
    state.states[2] = const CodeViewState(mode: CodeViewMode.code);
    await pump(tester);

    await tester.tap(find.text('beta new'));
    await settle(tester);

    expect(find.byType(CodeExplorer), findsNothing);
    expect(find.byType(PromptComposer), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('clicking a project name selects it; in Chat it opens its newest chat', (
    tester,
  ) async {
    final workspace = await pump(tester);

    await tester.tap(find.text('beta'));
    await settle(tester);

    expect(workspace.dataController.projectId, second);
    expect(workspace.dataController.sessionId, secondNew);
    expect(secondOld, isNot(secondNew));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('clicking a project name in Code shows its files', (tester) async {
    final workspace = await pump(tester);
    await code(tester);

    await tester.tap(find.text('beta'));
    await settle(tester);

    expect(workspace.dataController.projectId, second);
    expect(inExplorer('README.md'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('clicking the name of a collapsed project opens its group', (tester) async {
    final workspace = await pump(tester);
    await tester.tap(find.byTooltip('Collapse').last);
    await settle(tester);
    expect(find.text('beta new'), findsNothing);

    await tester.tap(find.text('beta'));
    await settle(tester);

    expect(find.text('beta new'), findsOneWidget);
    expect(workspace.dataController.collapsedProjects, isNot(contains(second)));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the chevron collapses without selecting', (tester) async {
    final workspace = await pump(tester);

    await tester.tap(find.byTooltip('Collapse').last);
    await settle(tester);

    expect(find.text('beta new'), findsNothing);
    expect(workspace.dataController.projectId, first);
    await disposeTestApp(tester, dependencies);
  });
}
