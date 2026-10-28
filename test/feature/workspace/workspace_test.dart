import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets('an empty workspace invites to open a project', (tester) async {
    useDesktopView(tester);
    final dependencies = testDependencies();
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('No projects yet'), findsOneWidget);
    expect(find.text('Open a project and start a chat with an agent'), findsOneWidget);
    expect(find.byTooltip('New chat'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('the workspace is localized to Russian', (tester) async {
    useDesktopView(tester);
    final dependencies = testDependencies();
    await tester.pumpWidget(
      testApp(
        const WorkspaceConfigWidget(),
        dependencies: dependencies,
        locale: const Locale('ru'),
        withSettings: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Проекты'), findsOneWidget);
    expect(find.text('Чаты'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('selecting a project shows its chats and opening one shows the composer', (
    tester,
  ) async {
    useDesktopView(tester);
    final dependencies = testDependencies();
    final database = dependencies.database;
    await tester.runAsync(() async {
      final project = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/work/avera-hotel', name: 'avera-hotel'));
      await database
          .into(database.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: project,
              agentId: 'claude',
              title: const Value<String>('Add a booking screen'),
            ),
          );
    });

    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('avera-hotel'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(find.text('Add a booking screen'), findsOneWidget);
    expect(find.text('Pick a chat or start a new one'), findsOneWidget);

    await tester.tap(find.text('Add a booking screen'));
    // The composer's blinking cursor never lets pumpAndSettle settle.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });
}
