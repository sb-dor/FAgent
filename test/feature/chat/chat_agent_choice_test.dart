import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets('picking another agent before the first message moves the chat to it', (
    tester,
  ) async {
    useDesktopView(tester);
    final dependencies = testDependencies();
    addTearDown(dependencies.database.close);
    final database = dependencies.database;
    final projectId = (await tester.runAsync(
      () => database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/tmp', name: 'p')),
    ))!;
    final sessionId = (await tester.runAsync(
      () => database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'claude')),
    ))!;
    await tester.pumpWidget(
      testApp(
        dependencies: dependencies,
        ChatConfigWidget(
          sessionId: sessionId,
          project: Project(id: projectId, path: '/tmp', name: 'p', isFlutter: false),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Claude Code'), findsOneWidget);

    await tester.tap(find.text('Claude Code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    final row = (await tester.runAsync(
      () => (database.select(
        database.sessionsTable,
      )..where((s) => s.id.equals(sessionId))).getSingle(),
    ))!;
    expect(row.agentId, 'codex');
    // The chat was loaded again for the new agent: the chip names it.
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Claude Code'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
