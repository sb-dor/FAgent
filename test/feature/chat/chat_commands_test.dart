import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  late Dependencies dependencies;

  setUp(() => dependencies = testDependencies());

  tearDown(() => dependencies.database.close());

  testWidgets('a command the agent announced is suggested after typing /', (tester) async {
    final database = dependencies.database;
    final projectId = await tester.runAsync(
      () => database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/tmp', name: 'p')),
    );
    final sessionId = await tester.runAsync(
      () => database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: projectId!, agentId: 'claude')),
    );
    await tester.pumpWidget(
      testApp(
        dependencies: dependencies,
        ChatConfigWidget(
          sessionId: sessionId!,
          project: Project(id: projectId!, path: '/tmp', name: 'p', isFlutter: false),
        ),
      ),
    );
    final live = await tester.runAsync(() => dependencies.agentHub.session(sessionId));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    live!.availableCommands.value = <Map<String, Object?>>[
      <String, Object?>{'name': 'compact', 'description': 'Compact the chat'},
    ];
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), '/comp');
    await tester.pump();

    expect(find.text('/compact'), findsOneWidget);
    expect(find.text('Compact the chat'), findsOneWidget);
  });
}
