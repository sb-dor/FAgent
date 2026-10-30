import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/chat_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_feed.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_item_view.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

Widget _item(ChatItem item, {Locale locale = const Locale('en'), Dependencies? dependencies}) =>
    testApp(
      Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: ChatItemView(item: item, onAnswerPermission: (_, _) {}),
        ),
      ),
      locale: locale,
      dependencies: dependencies,
    );

void main() {
  // Every test builds its own in-memory database.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('mentions in a user message become pills', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      _item(
        const UserMessageItem(
          0,
          text: 'fix @lib/a.dart now',
          resources: <String>['file:///p/lib/a.dart'],
        ),
      ),
    );

    final selectable = tester.widget<SelectableText>(
      find.descendant(of: find.byType(ChatItemView), matching: find.byType(SelectableText)),
    );
    final children = selectable.textSpan!.children!.cast<TextSpan>();
    expect(children.map((s) => s.text), <String?>['fix ', '@lib/a.dart', ' now']);
    final context = tester.element(find.byType(ChatItemView));
    expect(children[1].style?.backgroundColor, context.colors.accentSoft);
    // The old `@file` line under the text is gone.
    expect(find.text('@a.dart'), findsNothing);
  });

  testWidgets('an edit row shows added and removed lines', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      _item(
        const ToolCallItem(
          0,
          toolCallId: 't',
          title: 'Edit a.dart',
          kind: 'edit',
          status: 'completed',
          locations: <String>['/p/lib/a.dart'],
          content: <ToolContent>[
            ToolDiffContent(path: '/p/lib/a.dart', oldText: 'a\nb\nc', newText: 'a\nx\ny\nc'),
          ],
        ),
      ),
    );

    expect(find.text('+2 −1'), findsOneWidget);
    expect(find.text('/p/lib/a.dart'), findsOneWidget);
  });

  testWidgets('an edit without diffs has no counter', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      _item(const ToolCallItem(0, toolCallId: 't', title: 'Edit a.dart', kind: 'edit')),
    );

    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('a read group shows the count and expands to the paths', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      testApp(
        ChatFeed(
          items: <ChatItem>[
            for (var i = 0; i < 3; i++)
              ToolCallItem(
                i,
                toolCallId: 't$i',
                title: 'Read f$i.dart',
                kind: 'read',
                status: 'completed',
                locations: <String>['/p/lib/f$i.dart'],
              ),
          ],
          onAnswerPermission: (_, _) {},
        ),
      ),
    );

    expect(find.text('Read 3 files'), findsOneWidget);
    expect(find.text('/p/lib/f1.dart'), findsNothing);

    await tester.tap(find.text('Read 3 files'));
    await tester.pumpAndSettle();

    expect(find.text('/p/lib/f1.dart'), findsOneWidget);
    expect(find.text('/p/lib/f2.dart'), findsOneWidget);
  });

  testWidgets('the read count follows the Russian plural forms', (tester) async {
    useDesktopView(tester);
    final dependencies = testDependencies();
    for (final (count, label) in <(int, String)>[
      (2, 'Прочитал 2 файла'),
      (5, 'Прочитал 5 файлов'),
      (21, 'Прочитал 21 файл'),
    ]) {
      await tester.pumpWidget(
        testApp(
          ChatFeed(
            items: <ChatItem>[
              for (var i = 0; i < count; i++)
                ToolCallItem(i, toolCallId: 't$i', title: 'Read', kind: 'read'),
            ],
            onAnswerPermission: (_, _) {},
          ),
          locale: const Locale('ru'),
          dependencies: dependencies,
        ),
      );
      expect(find.text(label), findsOneWidget, reason: '$count');
    }
  });

  testWidgets('a thought shows its duration, or just the label without one', (tester) async {
    useDesktopView(tester);
    final dependencies = testDependencies();
    await tester.pumpWidget(
      _item(
        const AgentThoughtItem(0, text: 'hm', duration: Duration(milliseconds: 12900)),
        dependencies: dependencies,
      ),
    );
    expect(find.text('Thinking · 12 s'), findsOneWidget);

    await tester.pumpWidget(
      _item(
        const AgentThoughtItem(0, text: 'hm', duration: Duration(milliseconds: 600)),
        dependencies: dependencies,
      ),
    );
    expect(find.text('Thinking'), findsOneWidget);

    await tester.pumpWidget(
      _item(const AgentThoughtItem(0, text: 'hm'), dependencies: dependencies),
    );
    expect(find.text('Thinking'), findsOneWidget);

    await tester.pumpWidget(
      _item(
        const AgentThoughtItem(0, text: 'hm', duration: Duration(seconds: 12)),
        locale: const Locale('ru'),
        dependencies: dependencies,
      ),
    );
    expect(find.text('Размышления · 12 с'), findsOneWidget);
  });

  testWidgets('the feed column is at most 720 px', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      testApp(
        ChatFeed(
          items: <ChatItem>[AgentMessageItem(0, text: 'word ' * 400)],
          onAnswerPermission: (_, _) {},
        ),
      ),
    );

    final width = tester.getSize(find.byType(ChatItemView)).width;
    expect(width, lessThanOrEqualTo(kChatColumnWidth));
    expect(width, greaterThan(600));
  });

  testWidgets('an expanded read group stays open when a new item arrives', (tester) async {
    useDesktopView(tester);
    final dependencies = testDependencies();
    List<ChatItem> items(int extra) => <ChatItem>[
      for (var i = 0; i < 3; i++)
        ToolCallItem(
          i,
          toolCallId: 't$i',
          title: 'Read f$i.dart',
          kind: 'read',
          status: 'completed',
          locations: <String>['/p/lib/f$i.dart'],
        ),
      for (var i = 0; i < extra; i++) AgentMessageItem(10 + i, text: 'message $i'),
    ];
    Widget feed(int extra) => testApp(
      ChatFeed(items: items(extra), onAnswerPermission: (_, _) {}),
      dependencies: dependencies,
    );

    await tester.pumpWidget(feed(0));
    await tester.tap(find.text('Read 3 files'));
    await tester.pumpAndSettle();
    expect(find.text('/p/lib/f1.dart'), findsOneWidget);

    await tester.pumpWidget(feed(1));
    await tester.pumpWidget(feed(2));

    expect(find.text('message 1'), findsOneWidget);
    expect(find.text('/p/lib/f1.dart'), findsOneWidget);
  });

  testWidgets('rebuilding a tool call with the same diff reuses the computed lines', (
    tester,
  ) async {
    useDesktopView(tester);
    final dependencies = testDependencies();
    ToolCallItem call() => const ToolCallItem(
      0,
      toolCallId: 't',
      title: 'Edit a.dart',
      kind: 'edit',
      status: 'completed',
      content: <ToolContent>[ToolDiffContent(path: '/p/a.dart', oldText: 'a\nb', newText: 'a\nc')],
    );
    List<Object?> shownLines() => tester.widget<DiffView>(find.byType(DiffView)).lines!;

    await tester.pumpWidget(testApp(_card(call()), dependencies: dependencies));
    final first = shownLines();
    // A refolded feed holds equal but new objects.
    await tester.pumpWidget(testApp(_card(call()), dependencies: dependencies));

    expect(shownLines(), same(first));
  });
}

Widget _card(ToolCallItem call) => ChatItemView(item: call, onAnswerPermission: (_, _) {});
