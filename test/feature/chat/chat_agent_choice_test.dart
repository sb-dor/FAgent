import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
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
    // Model and mode are the agent's own and only known once it has started, for either agent.
    expect(find.byTooltip('Available after the agent starts'), findsNWidgets(2));
    // The chat was loaded again for the new agent: the chip names it.
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Claude Code'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the agent chip is locked while the chat is starting its agent', (tester) async {
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
    final live = (await tester.runAsync(() => dependencies.agentHub.session(sessionId)))!;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Agent'), findsOneWidget);

    // The first message is on its way: nothing is journaled yet, the agent is starting.
    live.status.value = SessionStatus.starting;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byTooltip("The agent can't be changed after the first message"), findsOneWidget);
    await tester.tap(find.text('Claude Code'));
    // The status line animates while the agent starts: no settling.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Codex'), findsNothing);

    // A chat that waits for a sign-in can still change its agent.
    live.status.value = SessionStatus.needsAuth;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Agent'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a chat of a removed agent cannot send, and keeps the typed text', (tester) async {
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
          .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'custom:9')),
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
    final live = (await tester.runAsync(() => dependencies.agentHub.session(sessionId)))!;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(live.problem.value?.kind, SessionProblemKind.removed);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded))
          .onPressed,
      isNull,
    );
    expect(find.text('hello'), findsOneWidget, reason: 'the draft stays in the composer');
    // The chat has no agent session, so it can still be moved to another agent.
    expect(find.byTooltip('Agent'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the agent chip is unlocked for a new chat that failed to start', (tester) async {
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
    final live = (await tester.runAsync(() => dependencies.agentHub.session(sessionId)))!;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));

    // The agent could not be started: the chat is in error and has no agent session.
    live
      ..problem.value = const SessionProblem(SessionProblemKind.start, 'npx not found')
      ..status.value = SessionStatus.error;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Agent'), findsOneWidget);

    live.status.value = SessionStatus.setupFailed;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Agent'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
