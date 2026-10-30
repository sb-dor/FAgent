import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late int projectId;
  late int existingChat;

  setUp(() => dependencies = testDependencies());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpShell(WidgetTester tester) async {
    useDesktopView(tester);
    await tester.runAsync(() async {
      final database = dependencies.database;
      projectId = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/p', name: 'p'));
      existingChat = await database
          .into(database.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: projectId,
              agentId: 'claude',
              title: const Value<String>('Old chat'),
            ),
          );
    });
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  WorkspaceConfigWidgetState workspaceOf(WidgetTester tester) =>
      WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

  Future<void> letChatLoad(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
  }

  String composerText(WidgetTester tester) =>
      tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget)).textController.text;

  testWidgets('createChat with a draft puts it into the new chat', (tester) async {
    await pumpShell(tester);

    workspaceOf(tester).createChat(projectId: projectId, draft: 'hello');
    await letChatLoad(tester);

    final data = workspaceOf(tester).dataController;
    expect(data.sessionId, isNotNull);
    expect(data.sessionId, isNot(existingChat));
    expect(composerText(tester), 'hello');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('createChat without a draft leaves the composer empty', (tester) async {
    await pumpShell(tester);

    workspaceOf(tester).createChat(projectId: projectId);
    await letChatLoad(tester);

    expect(workspaceOf(tester).dataController.sessionId, isNot(existingChat));
    expect(composerText(tester), isEmpty);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a draft is dropped when the user opens another chat first', (tester) async {
    await pumpShell(tester);
    final data = workspaceOf(tester).dataController..selectProject(projectId);

    workspaceOf(tester).createChat(projectId: projectId, draft: 'hello');
    data.selectSession(existingChat);
    await letChatLoad(tester);

    // The new chat is selected when it is created, and it has no draft.
    expect(data.sessionId, isNot(existingChat));
    expect(composerText(tester), isEmpty);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a draft does not leak into a later chat', (tester) async {
    await pumpShell(tester);

    workspaceOf(tester).createChat(projectId: projectId, draft: 'hello');
    await letChatLoad(tester);
    workspaceOf(tester).createChat(projectId: projectId);
    await letChatLoad(tester);

    expect(composerText(tester), isEmpty);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('createChat leaves Skills for the chat', (tester) async {
    await pumpShell(tester);
    final data = workspaceOf(tester).dataController..openView(WorkspaceView.skills);
    await tester.pump();

    workspaceOf(tester).createChat(projectId: projectId, draft: 'hello');
    await letChatLoad(tester);

    expect(data.view, WorkspaceView.chat);
    expect(composerText(tester), 'hello');
    await disposeTestApp(tester, dependencies);
  });
}
