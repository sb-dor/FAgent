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

  testWidgets('reject and say without a rejecting option does nothing', (tester) async {
    final chat = await pumpChat(tester);
    chat.composerFocus.unfocus();
    await tester.pump();

    chat.rejectAndSay(
      request(const <PermissionOptionView>[
        PermissionOptionView(optionId: 'ok', name: 'Allow', kind: 'allow_once'),
      ]),
    );
    await tester.pump();

    expect(chat.permissionController.state, isA<PermissionAnswer$InitialState>());
    expect(chat.composerFocus.hasFocus, isFalse);
  });
}
