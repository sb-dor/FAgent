import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/sessions/models/chat_session.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_chat_tile.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar_footer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  test('an agent is named after the list, else by its id', () {
    const agents = <AgentInfo>[
      AgentInfo(id: 'claude', name: 'Claude Code'),
      AgentInfo(id: 'custom:1', name: 'My agent'),
    ];

    expect(agentDisplayName('claude', agents), 'Claude Code');
    expect(agentDisplayName('custom:1', agents), 'My agent');
    expect(agentDisplayName('custom:9', agents), 'custom:9');
    expect(agentDisplayName('claude', const <AgentInfo>[]), 'claude');
  });

  Widget tile({required String agentId, String agentName = 'Codex'}) => testApp(
    WorkspaceChatTile(
      session: ChatSession(
        id: 1,
        projectId: 1,
        agentId: agentId,
        title: 'Booking screen',
        updatedAt: DateTime(2026, 11),
      ),
      agentName: agentName,
      selected: false,
      status: null,
      onTap: () {},
    ),
  );

  testWidgets('a chat of Codex shows a small agent label beside the title', (tester) async {
    await tester.pumpWidget(tile(agentId: 'codex'));

    expect(find.text('Booking screen'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
  });

  testWidgets('a chat of Claude shows no agent label', (tester) async {
    await tester.pumpWidget(tile(agentId: 'claude', agentName: 'Claude Code'));

    expect(find.text('Booking screen'), findsOneWidget);
    expect(find.text('Claude Code'), findsNothing);
  });

  testWidgets('a long title still ends with an ellipsis next to the label', (tester) async {
    tester.view
      ..physicalSize = const Size(240, 200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(tile(agentId: 'custom:3', agentName: 'My very own agent'));

    expect(tester.takeException(), isNull);
  });
}
