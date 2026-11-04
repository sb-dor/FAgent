import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/widgets/changes_view.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_view_state.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_explorer.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late int project;

  setUp(() {
    dependencies = testDependencies(
      codeFilesRepository: MemoryCodeFilesRepository(
        files: <String, String>{'/p/lib/main.dart': 'void main() {\n  run();\n}\n'},
      ),
    );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<WorkspaceConfigWidgetState> pump(WidgetTester tester) async {
    useDesktopView(tester);
    addTearDown(tester.view.reset);
    project = (await tester.runAsync(
      () => dependencies.database
          .into(dependencies.database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/p', name: 'p')),
    ))!;
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    final workspace = WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));
    workspace.dataController.selectProject(project);
    await settle(tester);
    return workspace;
  }

  testWidgets('a Changes file opens in Code and is revealed in the explorer', (tester) async {
    final workspace = await pump(tester);

    tester.widget<ChangesView>(find.byType(ChangesView)).onOpenFile('/p/lib/main.dart');
    await settle(tester);

    expect(workspace.codeWorkspace?.tabs.mode, CodeViewMode.code);
    expect(workspace.codeWorkspace?.tabs.active?.path, '/p/lib/main.dart');
    expect(
      find.descendant(of: find.byType(CodeExplorer), matching: find.text('main.dart')),
      findsOneWidget,
    );
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a Run log line opens at its line', (tester) async {
    final workspace = await pump(tester);

    await tester.runAsync(() => workspace.openRunFile('lib/main.dart', 2));
    await settle(tester);

    final active = workspace.codeWorkspace!.tabs.active!;
    expect(active.path, '/p/lib/main.dart');
    expect(active.editing.selection, const CodeLineSelection.collapsed(index: 1, offset: 0));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a path outside the project opens externally', (tester) async {
    final workspace = await pump(tester);

    await tester.runAsync(() => workspace.openInCode('/elsewhere/missing.txt'));
    await settle(tester);

    expect(workspace.codeWorkspace?.tabs.mode, CodeViewMode.chat);
    expect(workspace.codeWorkspace?.tabs.tabs, isEmpty);
    // The default app's path refuses a missing file before starting anything.
    expect(find.text('The file no longer exists.'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  group('removing a project with unsaved files', () {
    Future<WorkspaceConfigWidgetState> withUnsaved(WidgetTester tester) async {
      final workspace = await pump(tester);
      final document = (await tester.runAsync(
        () => workspace.codeWorkspace!.tabs.open('/p/lib/main.dart'),
      ))!;
      document.editing.replaceSelection('x');
      await settle(tester);
      final p = switch (workspace.projectsController.state) {
        Projects$CompletedState(:final projects) => projects.single,
        _ => throw StateError('no project'),
      };
      workspace.removeProject(p).ignore();
      await settle(tester);
      return workspace;
    }

    testWidgets('asks first; Cancel keeps the project and the files', (tester) async {
      await withUnsaved(tester);

      expect(find.text('1 file has unsaved changes.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(find.textContaining('Remove'), findsNothing);
      expect(dependencies.codeViews.count(projectId: project), 1);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets("Don't save, then Remove, drops the files", (tester) async {
      await withUnsaved(tester);

      await tester.tap(find.text("Don't save"));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await settle(tester);
      await settle(tester);

      expect(dependencies.codeViews.count(), 0);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Save saves before asking to remove', (tester) async {
      final workspace = await withUnsaved(tester);
      final document = workspace.codeWorkspace!.tabs.active!;

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      expect(document.dirty, isFalse);
      expect(find.widgetWithText(FilledButton, 'Remove'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });
  });
}
