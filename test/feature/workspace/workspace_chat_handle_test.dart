import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
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
  late List<int> chats;

  setUp(() => dependencies = testDependencies());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    chats = (await tester.runAsync(() async {
      final database = dependencies.database;
      final project = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/p', name: 'p'));
      return <int>[
        for (final title in <String>['First chat', 'Second chat'])
          await database
              .into(database.sessionsTable)
              .insert(
                SessionsTableCompanion.insert(
                  projectId: project,
                  agentId: 'claude',
                  title: Value<String>(title),
                ),
              ),
      ];
    }))!;
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    await tester.pumpAndSettle();
  }

  WorkspaceConfigWidgetState workspaceOf(WidgetTester tester) =>
      WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

  WorkspaceDataController dataOf(WidgetTester tester) => workspaceOf(tester).dataController;

  Future<void> open(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
  }

  ChatHandle handleFor(int sessionId, {ValueChanged<String>? onInsert}) => ChatHandle(
    sessionId: sessionId,
    view: ChatView(
      sessionId: sessionId,
      agentId: 'claude',
      items: const [],
      status: SessionStatus.idle,
    ),
    insertDraft: onInsert ?? (_) {},
  );

  testWidgets('the selected chat publishes its view', (tester) async {
    await pumpShell(tester);
    expect(dataOf(tester).chatHandle.value, isNull);

    await open(tester, 'First chat');
    expect(dataOf(tester).chatHandle.value?.sessionId, chats[0]);
    expect(dataOf(tester).chatHandle.value?.view.sessionId, chats[0]);

    await open(tester, 'Second chat');
    expect(dataOf(tester).chatHandle.value?.sessionId, chats[1]);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a handle of another chat is ignored', (tester) async {
    await pumpShell(tester);
    await open(tester, 'First chat');
    final published = dataOf(tester).chatHandle.value;

    dataOf(tester).publishChatHandle(handleFor(chats[1]));

    expect(dataOf(tester).chatHandle.value, same(published));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('no selected chat means no handle', (tester) async {
    await pumpShell(tester);
    await open(tester, 'First chat');
    expect(dataOf(tester).chatHandle.value, isNotNull);

    dataOf(tester).selectSession(null);
    expect(dataOf(tester).chatHandle.value, isNull);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a handle notifies only its own listeners', (tester) async {
    final controller = WorkspaceDataController()..selectSession(7);
    var controllerNotified = 0;
    var handleNotified = 0;
    controller
      ..addListener(() => controllerNotified++)
      ..chatHandle.addListener(() => handleNotified++)
      ..publishChatHandle(handleFor(7));

    expect(handleNotified, 1);
    expect(controllerNotified, 0);
    controller.dispose();
  });

  group('insertDraft', () {
    Future<(ChatHandle, ChatConfigWidgetState)> openChat(WidgetTester tester) async {
      await pumpShell(tester);
      await open(tester, 'First chat');
      return (
        dataOf(tester).chatHandle.value!,
        tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget)),
      );
    }

    testWidgets('puts text into an empty composer and focuses it', (tester) async {
      final (handle, chat) = await openChat(tester);
      chat.composerFocus.unfocus();
      await tester.pump();

      handle.insertDraft('Fix this');
      await tester.pump();

      expect(chat.textController.text, 'Fix this');
      expect(chat.textController.selection, const TextSelection.collapsed(offset: 8));
      expect(chat.composerFocus.hasFocus, isTrue);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('adds text after a blank line to a non-empty composer', (tester) async {
      final (handle, chat) = await openChat(tester);
      chat.textController.text = 'hi';

      handle.insertDraft('Fix this');
      await tester.pump();

      expect(chat.textController.text, 'hi\n\nFix this');
      expect(chat.textController.selection, const TextSelection.collapsed(offset: 12));
      await disposeTestApp(tester, dependencies);
    });
  });

  testWidgets('clicking an edit row opens its file in Changes', (tester) async {
    await pumpShell(tester);
    await open(tester, 'First chat');
    await tester.runAsync(() async {
      final live = await dependencies.agentHub.session(chats[0]);
      await live.store.addDurable(SessionEventOrigin.agent, 'tool_call', <String, Object?>{
        'params': <String, Object?>{
          'update': <String, Object?>{
            'toolCallId': 't1',
            'title': 'Edit a.dart',
            'kind': 'edit',
            'status': 'completed',
            'locations': <Object?>['/p/lib/a.dart'],
            'content': <Object?>[
              <String, Object?>{
                'type': 'diff',
                'path': '/p/lib/a.dart',
                'oldText': 'a',
                'newText': 'b',
              },
            ],
          },
        },
      });
    });
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    final data = dataOf(tester);
    workspaceOf(tester).settingsController.update((s) => s.copyWith(rightPaneVisible: false));
    await settle(tester);
    data.selectPaneTab(RightPaneTab.plan);

    await tester.tap(find.byTooltip('Open in Changes'));
    await settle(tester);

    expect(data.paneTab, RightPaneTab.changes);
    expect(data.selectedChangePath, '/p/lib/a.dart');
    expect(workspaceOf(tester).settingsController.settings.rightPaneVisible, isTrue);
    await disposeTestApp(tester, dependencies);
  });
}
