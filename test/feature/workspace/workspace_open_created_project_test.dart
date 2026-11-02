import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/new_project_dialog.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_project_creation_repository.dart';
import '../../support/test_app.dart';

const _step = Duration(milliseconds: 10);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late MemoryProjectCreationRepository memory;
  late int otherProjectId;
  late int createdProjectId;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> elapse(WidgetTester tester, Duration duration) async {
    for (var left = duration; left > Duration.zero; left -= const Duration(milliseconds: 50)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpShell(WidgetTester tester) async {
    useDesktopView(tester);
    memory = MemoryProjectCreationRepository(step: _step);
    dependencies = testDependencies(projectCreationRepository: memory);
    await tester.runAsync(() async {
      final database = dependencies.database;
      otherProjectId = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/other', name: 'other'));
      // The creation adds its project itself; the test stands in for that.
      createdProjectId = await database
          .into(database.projectsTable)
          .insert(
            ProjectsTableCompanion.insert(path: '/work/avera_booking', name: 'avera_booking'),
          );
    });
    memory.completedProjectId = createdProjectId;
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  WorkspaceConfigWidgetState workspaceOf(WidgetTester tester) =>
      WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

  /// Creates `avera_booking` through the wizard and waits until it has finished.
  Future<void> createProject(WidgetTester tester, {required bool openChat}) async {
    await tester.tap(find.text('Project'));
    await elapse(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('New Flutter project…'));
    await elapse(tester, const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey<String>('new-project-name')), 'avera_booking');
    await tester.pumpAndSettle();
    if (!openChat) {
      await tester.tap(find.byKey(const ValueKey<String>('new-project-chat')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey<String>('new-project-create')));
    await tester.pump();
    await elapse(tester, const Duration(seconds: 2));
    expect(find.byKey(const ValueKey<String>('creation-open-project')), findsOneWidget);
  }

  Future<int> chatCount(WidgetTester tester, int projectId) => tester
      .runAsync(() async {
        final database = dependencies.database;
        final rows = await (database.select(
          database.sessionsTable,
        )..where((table) => table.projectId.equals(projectId))).get();
        return rows.length;
      })
      .then((count) => count!);

  testWidgets('open project with chat starts a chat', (tester) async {
    await pumpShell(tester);
    final data = workspaceOf(tester).dataController..selectProject(otherProjectId);
    await tester.pump();
    await createProject(tester, openChat: true);

    await tester.tap(find.byKey(const ValueKey<String>('creation-open-project')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }

    expect(find.byType(NewProjectDialog), findsNothing);
    expect(workspaceOf(tester).projectCreation.state, isA<ProjectCreation$IdleState>());
    expect(data.projectId, createdProjectId);
    expect(data.sessionId, isNotNull);
    expect(await chatCount(tester, createdProjectId), 1);
    expect(await chatCount(tester, otherProjectId), 0);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('open project without chat only selects it', (tester) async {
    await pumpShell(tester);
    final data = workspaceOf(tester).dataController..selectProject(otherProjectId);
    await tester.pump();
    await createProject(tester, openChat: false);

    await tester.tap(find.byKey(const ValueKey<String>('creation-open-project')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }

    expect(find.byType(NewProjectDialog), findsNothing);
    expect(workspaceOf(tester).projectCreation.state, isA<ProjectCreation$IdleState>());
    expect(data.projectId, createdProjectId);
    expect(await chatCount(tester, createdProjectId), 0);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('open project leaves Settings for the chat view', (tester) async {
    await pumpShell(tester);
    final data = workspaceOf(tester).dataController;
    await createProject(tester, openChat: false);
    data.openView(WorkspaceView.settings);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('creation-open-project')));
    await tester.pumpAndSettle();

    expect(data.view, WorkspaceView.chat);
    expect(data.projectId, createdProjectId);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('close leaves the selection alone', (tester) async {
    await pumpShell(tester);
    final data = workspaceOf(tester).dataController..selectProject(otherProjectId);
    await tester.pump();
    await createProject(tester, openChat: true);

    await tester.tap(find.byKey(const ValueKey<String>('creation-close')));
    await tester.pumpAndSettle();

    expect(find.byType(NewProjectDialog), findsNothing);
    expect(workspaceOf(tester).projectCreation.state, isA<ProjectCreation$IdleState>());
    expect(data.projectId, otherProjectId);
    expect(await chatCount(tester, createdProjectId), 0);
    await disposeTestApp(tester, dependencies);
  });
}
