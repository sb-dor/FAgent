import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/sessions/models/chat_session.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_chat_tile.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar_footer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('an agent is named after the list; a removed custom one says so', (tester) async {
    const agents = <AgentInfo>[
      AgentInfo(id: 'claude', name: 'Claude Code'),
      AgentInfo(id: 'custom:1', name: 'My agent'),
    ];
    final names = <String>[];
    Widget namesApp(Locale locale) => testApp(
      locale: locale,
      Builder(
        builder: (context) {
          final localization = Localization.of(context);
          names
            ..clear()
            ..addAll(<String>[
              agentDisplayName('claude', agents, localization),
              agentDisplayName('custom:1', agents, localization),
              agentDisplayName('custom:9', agents, localization),
              agentDisplayName('claude', const <AgentInfo>[], localization),
            ]);
          return const SizedBox.shrink();
        },
      ),
    );

    await tester.pumpWidget(namesApp(const Locale('en')));
    expect(names, <String>['Claude Code', 'My agent', 'Removed agent', 'claude']);

    await tester.pumpWidget(namesApp(const Locale('ru')));
    await tester.pump();
    expect(names, <String>['Claude Code', 'My agent', 'Удалённый агент', 'claude']);
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

  testWidgets('a chat has no ink: a click selects it, a right click opens the menu', (
    tester,
  ) async {
    var taps = 0;
    Rect? menu;
    await tester.pumpWidget(
      testApp(
        WorkspaceChatTile(
          session: ChatSession(
            id: 1,
            projectId: 1,
            agentId: 'claude',
            title: 'Booking screen',
            updatedAt: DateTime(2026, 11),
          ),
          agentName: 'Claude Code',
          selected: true,
          status: null,
          onTap: () => taps++,
          onMenu: (anchor) => menu = anchor,
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(WorkspaceChatTile),
        // InkWell and every other ink widget is an InkResponse.
        matching: find.byWidgetPredicate((widget) => widget is InkResponse),
      ),
      // Only the ⋯ button's own one, which shows no splash or highlight.
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byWidgetPredicate((widget) => widget is InkResponse),
        matching: find.byType(IconButton),
      ),
      findsOneWidget,
    );
    final dots = tester.widget<IconButton>(find.byType(IconButton));
    expect(dots.style?.splashFactory, NoSplash.splashFactory);
    await tester.tap(find.text('Booking screen'));
    await tester.pump();
    expect(taps, 1);
    await tester.tap(find.text('Booking screen'), buttons: kSecondaryButton);
    await tester.pump();
    expect(menu, isNotNull);
  });

  testWidgets('hovering a chat changes neither its size nor its color', (tester) async {
    await tester.pumpWidget(
      testApp(
        WorkspaceChatTile(
          session: ChatSession(
            id: 1,
            projectId: 1,
            agentId: 'claude',
            title: 'Booking screen',
            updatedAt: DateTime(2026, 11),
          ),
          agentName: 'Claude Code',
          selected: false,
          status: null,
          onTap: () {},
          onMenu: (_) {},
        ),
      ),
    );
    Color? background() =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(WorkspaceChatTile),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .color;
    final size = tester.getSize(find.byType(WorkspaceChatTile));
    final color = background();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Booking screen')));
    await tester.pump();

    expect(find.byTooltip('Chat actions'), findsOneWidget);
    expect(tester.getSize(find.byType(WorkspaceChatTile)), size);
    expect(background(), color);
  });

  testWidgets('the selected chat keeps its color', (tester) async {
    Widget tileOf({required bool selected}) => testApp(
      WorkspaceChatTile(
        session: ChatSession(
          id: 1,
          projectId: 1,
          agentId: 'claude',
          title: 'Booking screen',
          updatedAt: DateTime(2026, 11),
        ),
        agentName: 'Claude Code',
        selected: selected,
        status: null,
        onTap: () {},
      ),
    );
    Color? background() =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(WorkspaceChatTile),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .color;

    await tester.pumpWidget(tileOf(selected: false));
    final plain = background();
    await tester.pumpWidget(tileOf(selected: true));

    expect(background(), isNot(plain));
    expect(background()!.a, greaterThan(0));
  });
}
