import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/sessions/models/chat_session.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_chat_tile.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar_footer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

  Widget tile({
    required String agentId,
    String agentName = 'Codex',
    String title = 'Booking screen',
  }) => testApp(
    WorkspaceChatTile(
      session: ChatSession(
        id: 1,
        projectId: 1,
        agentId: agentId,
        title: title,
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

  testWidgets('a long title ends with an ellipsis and the label keeps its place', (tester) async {
    tester.view
      ..physicalSize = const Size(240, 200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const title = 'A very long chat title that cannot possibly fit into the narrow sidebar tile';
    await tester.pumpWidget(
      tile(agentId: 'custom:3', agentName: 'My very own agent', title: title),
    );

    expect(tester.takeException(), isNull);
    final titleText = tester.widget<Text>(find.text(title));
    expect(titleText.overflow, TextOverflow.ellipsis);
    expect(titleText.maxLines, 1);
    expect(tester.renderObject<RenderParagraph>(find.text(title)).didExceedMaxLines, isTrue);
    final label = tester.widget<Text>(find.text('My very own agent'));
    expect(label.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.text('My very own agent')).width, lessThanOrEqualTo(72));
  });
}
