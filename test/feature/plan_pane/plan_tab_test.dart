import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/plan_pane/widgets/plan_tab.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  PlanItem plan(int seq, List<(String, String)> entries) => PlanItem(
    seq,
    entries: <PlanEntry>[
      for (final (content, status) in entries) PlanEntry(content: content, status: status),
    ],
  );

  testWidgets('the latest plan is shown with progress', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      testApp(
        PlanTab(
          items: <ChatItem>[
            plan(1, <(String, String)>[('Old step', 'completed')]),
            const AgentMessageItem(2, text: 'working'),
            plan(3, <(String, String)>[
              ('Read the code', 'completed'),
              ('Write the tests', 'completed'),
              ('Implement', 'in_progress'),
            ]),
          ],
        ),
      ),
    );

    expect(find.text('Old step'), findsNothing);
    expect(find.text('Read the code'), findsOneWidget);
    expect(find.text('Write the tests'), findsOneWidget);
    expect(find.text('Implement'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a pending step has a muted outline icon', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      testApp(
        PlanTab(
          items: <ChatItem>[
            plan(1, <(String, String)>[('Later', 'pending')]),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
  });

  testWidgets('without a plan the tab explains it', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      testApp(const PlanTab(items: <ChatItem>[AgentMessageItem(1, text: 'hi')])),
    );

    expect(find.text('No plan yet'), findsOneWidget);
  });

  testWidgets('an empty plan counts as no plan', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      testApp(PlanTab(items: <ChatItem>[plan(1, const <(String, String)>[])])),
    );

    expect(find.text('No plan yet'), findsOneWidget);
  });

  testWidgets('long entries wrap without overflow at 340 px', (tester) async {
    tester.view
      ..physicalSize = const Size(340, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final long = List.filled(30, 'extraordinarily_long_step').join(' ');
    await tester.pumpWidget(
      testApp(
        PlanTab(
          items: <ChatItem>[
            plan(1, <(String, String)>[
              (long, 'in_progress'),
              ('x' * 200, 'pending'),
              (long, 'completed'),
            ]),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(long), findsNWidgets(2));
  });

  group('in the right pane', () {
    late Dependencies dependencies;
    late int sessionId;

    setUp(() => dependencies = testDependencies());

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<WorkspaceConfigWidgetState> pump(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      sessionId = (await tester.runAsync(() async {
        final database = dependencies.database;
        final project = await database
            .into(database.projectsTable)
            .insert(ProjectsTableCompanion.insert(path: '/p', name: 'p'));
        return database
            .into(database.sessionsTable)
            .insert(
              SessionsTableCompanion.insert(
                projectId: project,
                agentId: 'claude',
                title: const Value<String>('Chat'),
              ),
            );
      }))!;
      await tester.pumpWidget(
        testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat'));
      for (var i = 0; i < 5; i++) {
        await settle(tester);
      }
      return WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));
    }

    void publish(WorkspaceConfigWidgetState state, List<ChatItem> items) =>
        state.dataController.publishChatHandle(
          ChatHandle(
            sessionId: sessionId,
            view: ChatView(
              sessionId: sessionId,
              agentId: 'claude',
              items: items,
              status: SessionStatus.idle,
            ),
            insertDraft: (_) {},
          ),
        );

    testWidgets('the Plan tab follows the open chat', (tester) async {
      final state = await pump(tester);
      state.dataController.selectPaneTab(RightPaneTab.plan);
      await tester.pump();
      expect(find.text('No plan yet'), findsOneWidget);

      publish(state, <ChatItem>[
        plan(1, <(String, String)>[('One', 'completed'), ('Two', 'pending')]),
      ]);
      await tester.pump();
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);

      publish(state, <ChatItem>[
        plan(1, <(String, String)>[('One', 'completed'), ('Two', 'completed')]),
      ]);
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });
  });
}
