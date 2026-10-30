import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/permission_broker.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/permission_request/controller/permission_answer_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  late Dependencies dependencies;

  setUp(() {
    dependencies = testDependencies();
    addTearDown(dependencies.database.close);
  });

  PermissionItem request(List<PermissionOptionView> options) =>
      PermissionItem(1, requestId: 'claude#1#7', title: 'Run ls', options: options);

  /// A chat on a stored session (no agent is started), with its composer on screen.
  int? lastSessionId;

  Future<ChatConfigWidgetState> pumpChat(WidgetTester tester) async {
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
    lastSessionId = sessionId;
    await tester.runAsync(() => dependencies.agentHub.session(sessionId));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    return tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));
  }

  testWidgets('reject and say declines and focuses the composer', (tester) async {
    final chat = await pumpChat(tester);
    chat.composerFocus.unfocus();
    await tester.pump();
    expect(chat.composerFocus.hasFocus, isFalse);
    expect(chat.permissionController.state, isA<PermissionAnswer$InitialState>());

    chat.rejectAndSay(
      request(const <PermissionOptionView>[
        PermissionOptionView(optionId: 'ok', name: 'Allow', kind: 'allow_once'),
        PermissionOptionView(optionId: 'no', name: 'Reject', kind: 'reject_once'),
      ]),
    );
    await tester.pump();

    expect(chat.permissionController.state, isA<PermissionAnswer$CompletedState>());
    expect(chat.composerFocus.hasFocus, isTrue);
  });

  testWidgets('reject and say without reject_once does nothing', (tester) async {
    final chat = await pumpChat(tester);
    chat.composerFocus.unfocus();
    await tester.pump();

    chat.rejectAndSay(
      request(const <PermissionOptionView>[
        PermissionOptionView(optionId: 'ok', name: 'Allow', kind: 'allow_once'),
        PermissionOptionView(optionId: 'never', name: 'Never', kind: 'reject_always'),
      ]),
    );
    await tester.pump();

    expect(chat.permissionController.state, isA<PermissionAnswer$InitialState>());
    expect(chat.composerFocus.hasFocus, isFalse);
  });

  group('a request waiting in the chat', () {
    const requestId = 'claude#1#9';

    /// Options in a deliberately scrambled order, so only the kinds decide.
    const full = <Map<String, Object?>>[
      <String, Object?>{'optionId': 'always', 'name': 'Always', 'kind': 'allow_always'},
      <String, Object?>{'optionId': 'never', 'name': 'Never', 'kind': 'reject_always'},
      <String, Object?>{'optionId': 'once', 'name': 'Once', 'kind': 'allow_once'},
      <String, Object?>{'optionId': 'no', 'name': 'No', 'kind': 'reject_once'},
    ];

    /// Shows the request in the feed and returns what the user decided (`null` while open).
    Future<PermissionDecision? Function()> pumpRequest(
      WidgetTester tester,
      List<Map<String, Object?>> options,
    ) async {
      await pumpChat(tester);
      final sessionId = lastSessionId!;
      PermissionDecision? decision;
      await tester.runAsync(() async {
        dependencies.agentHub.permissions
            .wait(requestId, sessionId: sessionId)
            .then((d) => decision = d)
            .ignore();
        final live = await dependencies.agentHub.session(sessionId);
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
              'options': options,
            },
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Run this command?'), findsOneWidget);
      return () => decision;
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(key);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }

    testWidgets('Enter in the empty composer answers with allow_once', (tester) async {
      final decision = await pumpRequest(tester, full);

      await press(tester, LogicalKeyboardKey.enter);

      expect(decision(), isA<PermissionSelected>().having((d) => d.optionId, 'optionId', 'once'));
    });

    testWidgets('Escape in the empty composer answers with reject_once', (tester) async {
      final decision = await pumpRequest(tester, full);

      await press(tester, LogicalKeyboardKey.escape);

      expect(decision(), isA<PermissionSelected>().having((d) => d.optionId, 'optionId', 'no'));
    });

    testWidgets('Enter without allow_once answers nothing', (tester) async {
      final decision = await pumpRequest(tester, <Map<String, Object?>>[full[0], full[3]]);

      await press(tester, LogicalKeyboardKey.enter);

      expect(decision(), isNull);
    });

    testWidgets('Escape without reject_once answers nothing and the card has no Esc hint', (
      tester,
    ) async {
      final decision = await pumpRequest(tester, <Map<String, Object?>>[full[0], full[1]]);

      await press(tester, LogicalKeyboardKey.escape);

      expect(decision(), isNull);
      expect(find.text('Esc'), findsNothing);
    });

    testWidgets('Command+Enter in the empty composer does not allow', (tester) async {
      final decision = await pumpRequest(tester, full);
      await tester.tap(find.byType(TextField));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

      expect(decision(), isNull);
    });

    testWidgets('the card of the waiting request shows the Enter and Esc hints', (tester) async {
      await pumpRequest(tester, full);

      expect(find.text('↵'), findsOneWidget);
      expect(find.text('Esc'), findsOneWidget);
    });

    testWidgets('a draft keeps Enter and Escape from answering', (tester) async {
      final decision = await pumpRequest(tester, full);
      await tester.enterText(find.byType(TextField), 'wait');

      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.escape);

      expect(decision(), isNull);
    });

    testWidgets('the Reject and say button declines with reject_once and focuses the composer', (
      tester,
    ) async {
      final decision = await pumpRequest(tester, full);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, 'Reject and say…'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(decision(), isA<PermissionSelected>().having((d) => d.optionId, 'optionId', 'no'));
      expect(
        tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget)).composerFocus.hasFocus,
        isTrue,
      );
    });

    testWidgets('Reject and say is absent without reject_once', (tester) async {
      await pumpRequest(tester, <Map<String, Object?>>[full[2], full[1]]);

      expect(find.text('Reject and say…'), findsNothing);
    });
  });
}
