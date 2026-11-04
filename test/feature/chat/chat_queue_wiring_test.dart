import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/permission_broker.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  late Dependencies dependencies;
  late int projectId;

  setUp(() {
    dependencies = testDependencies();
    addTearDown(dependencies.database.close);
  });

  Future<int> newChat(WidgetTester tester) async {
    final database = dependencies.database;
    return (await tester.runAsync(
      () => database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'claude')),
    ))!;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    // The feed refolds on a timer of the test's clock.
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Shows chat [sessionId] (no agent is started) and returns its runtime state.
  Future<LiveSession> show(WidgetTester tester, int sessionId) async {
    await tester.pumpWidget(
      testApp(
        dependencies: dependencies,
        ChatConfigWidget(
          key: ValueKey<int>(sessionId),
          sessionId: sessionId,
          project: Project(
            id: projectId,
            path: '/tmp',
            name: 'p',
            isFlutter: false,
            trustedAt: DateTime(2026),
          ),
        ),
      ),
    );
    final live = (await tester.runAsync(() => dependencies.agentHub.session(sessionId)))!;
    await settle(tester);
    return live;
  }

  Future<void> commandEnter(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(tester);
  }

  Future<void> setUpProject(WidgetTester tester) async {
    final database = dependencies.database;
    projectId = (await tester.runAsync(
      () => database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/tmp', name: 'p')),
    ))!;
  }

  ChatConfigWidgetState chatState(WidgetTester tester) =>
      tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));

  testWidgets('⌘↵ while the agent works shows the message above the composer', (tester) async {
    await setUpProject(tester);
    final live = await show(tester, await newChat(tester));
    live.status.value = SessionStatus.running;
    await settle(tester);
    expect(find.text('The agent is working — ⌘↵ queues your message'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'then add tests');
    await commandEnter(tester);

    expect(chatState(tester).textController.text, isEmpty);
    expect(find.text('then add tests'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('then add tests')).dy,
      lessThan(tester.getTopLeft(find.byType(TextField)).dy),
    );
  });

  testWidgets('⌘↵ while a permission waits queues and leaves the request open', (tester) async {
    await setUpProject(tester);
    final sessionId = await newChat(tester);
    final live = await show(tester, sessionId);
    const requestId = 'claude#1#9';
    PermissionDecision? decision;
    await tester.runAsync(() async {
      dependencies.agentHub.permissions
          .wait(requestId, sessionId: sessionId)
          .then((d) => decision = d)
          .ignore();
      await live.store.addDurable(
        SessionEventOrigin.agent,
        SessionEventKind.permissionRequest,
        <String, Object?>{
          'requestId': requestId,
          'params': <String, Object?>{
            'toolCall': <String, Object?>{
              'title': 'Run ls',
              'rawInput': <String, Object?>{'command': 'ls'},
            },
            'options': <Map<String, Object?>>[
              <String, Object?>{'optionId': 'once', 'name': 'Once', 'kind': 'allow_once'},
              <String, Object?>{'optionId': 'no', 'name': 'No', 'kind': 'reject_once'},
            ],
          },
        },
      );
    });
    live.status.value = SessionStatus.awaitingPermission;
    await settle(tester);
    expect(find.text('Run this command?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'after that');
    await commandEnter(tester);

    expect(decision, isNull);
    expect(chatState(tester).queueController.state.items.single.text, 'after that');
  });

  testWidgets('a second ⌘↵ while the first is still being prepared queues nothing more', (
    tester,
  ) async {
    await setUpProject(tester);
    final live = await show(tester, await newChat(tester));
    live.status.value = SessionStatus.running;
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'once');
    final chat = chatState(tester);

    await tester.runAsync(() => Future.wait(<Future<void>>[chat.queue(), chat.queue()]));
    await settle(tester);

    expect(chat.queueController.state.items.map((p) => p.text), <String>['once']);
  });

  testWidgets('Stop pauses the queue', (tester) async {
    await setUpProject(tester);
    final live = await show(tester, await newChat(tester));
    live.status.value = SessionStatus.running;
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'next');
    await commandEnter(tester);

    await tester.tap(find.byTooltip('Stop'));
    await settle(tester);
    // The agent ends the cancelled turn.
    live.status.value = SessionStatus.idle;
    await settle(tester);

    expect(find.text('Queue paused'), findsOneWidget);
    expect(live.lastPrompt, isNull);
    // Lets the hub's stop deadline pass.
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('a queued message of chat A goes to A after the user switched to chat B', (
    tester,
  ) async {
    await setUpProject(tester);
    final chatA = await newChat(tester);
    final chatB = await newChat(tester);
    final liveA = await show(tester, chatA);
    liveA.status.value = SessionStatus.running;
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'for chat A');
    await commandEnter(tester);

    final liveB = await show(tester, chatB);
    expect(find.text('for chat A'), findsNothing);
    expect(dependencies.chatQueues.sessionIds, <int>{chatA});

    // A's turn ends while B is on screen.
    liveA.status.value = SessionStatus.idle;
    await settle(tester);

    expect(liveA.lastPrompt?.first, <String, Object?>{'type': 'text', 'text': 'for chat A'});
    expect(liveB.lastPrompt, isNull);
    expect(dependencies.chatQueues.sessionIds, isEmpty);
  });
}
