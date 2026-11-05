import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_rules/widgets/project_rules_dialog.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_project_rules.dart';
import '../../support/memory_skills_repository.dart';
import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late FakeProjectRules rules;
  late int first;
  late int second;

  setUp(() {
    rules = FakeProjectRules();
    dependencies = testDependencies(projectRulesRepository: rules);
  });

  /// Lets the database and the controllers answer, and a dialog animate in or out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<WorkspaceConfigWidgetState> pump(WidgetTester tester) async {
    useDesktopView(tester);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final db = dependencies.database;
      first = await db
          .into(db.projectsTable)
          .insert(
            ProjectsTableCompanion.insert(
              path: '/p',
              name: 'alpha',
              isFlutter: const Value<bool>(true),
            ),
          );
      second = await db
          .into(db.projectsTable)
          .insert(
            ProjectsTableCompanion.insert(
              path: '/q',
              name: 'beta',
              isFlutter: const Value<bool>(true),
            ),
          );
    });
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    return WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));
  }

  Future<void> markOffered(WidgetTester tester, int projectId) => tester.runAsync(
    () =>
        (dependencies.database.update(dependencies.database.projectsTable)
              ..where((p) => p.id.equals(projectId)))
            .write(const ProjectsTableCompanion(rulesOffered: Value<bool>(true))),
  );

  testWidgets('selecting a project without docs/rules shows the dialog once', (tester) async {
    final workspace = await pump(tester);

    workspace.dataController.selectProject(first);
    await settle(tester);
    expect(find.byType(ProjectRulesDialog), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await settle(tester);
    expect(find.byType(ProjectRulesDialog), findsNothing);
    expect(rules.offered, <int>[first]);
    await markOffered(tester, first);

    workspace.dataController.selectProject(second);
    await settle(tester);
    await tester.tap(find.text('Not now'));
    await settle(tester);
    workspace.dataController.selectProject(first);
    await settle(tester);

    expect(find.byType(ProjectRulesDialog), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('Add writes the chosen rules into the project', (tester) async {
    final workspace = await pump(tester);
    workspace.dataController.selectProject(first);
    await settle(tester);

    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(rules.written.single.$1, '/p');
    expect(rules.written.single.$2, <String>['a']);
    expect(rules.offered, <int>[first]);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('switching projects while it loads offers only the selected one', (tester) async {
    final workspace = await pump(tester);
    rules.hold = Completer<void>();

    workspace.dataController.selectProject(first);
    await settle(tester);
    workspace.dataController.selectProject(second);
    await settle(tester);
    rules.hold!.complete();
    rules.hold = null;
    await settle(tester);

    // One dialog, for the selected project: Add writes into /q only.
    expect(find.byType(ProjectRulesDialog), findsOneWidget);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(rules.written.map((write) => write.$1), <String>['/q']);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the Rules section shows Add rules to project for such a project', (tester) async {
    final workspace = await pump(tester);
    await markOffered(tester, first);
    await settle(tester);
    workspace.dataController
      ..selectProject(first)
      ..openView(WorkspaceView.skills, section: 'rules');
    await settle(tester);
    expect(find.byType(ProjectRulesDialog), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('skills-add-project-rules')));
    await settle(tester);

    expect(find.byType(ProjectRulesDialog), findsOneWidget);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(rules.written.single.$1, '/p');
    expect(find.byKey(const ValueKey<String>('skills-add-project-rules')), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets("a built-in rule's switch says Added to new projects", (tester) async {
    dependencies = testDependencies(
      projectRulesRepository: FakeProjectRules(allHaveRules: true),
      skillsRepository: MemorySkillsRepository(
        items: [memoryRule('architecture', description: 'Layout.')],
        texts: {'rule:builtin:architecture': '# Architecture\n'},
      ),
    );
    final workspace = await pump(tester);
    workspace.dataController
      ..selectProject(first)
      ..openView(WorkspaceView.skills, section: 'rules');
    await settle(tester);

    await tester.tap(find.text('architecture').first);
    await settle(tester);

    expect(find.text('Added to new projects'), findsOneWidget);
    // Per-project switches do nothing for a built-in rule: they are not shown.
    expect(find.text('All projects'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });
}
