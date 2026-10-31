import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_code_agent/src/common/constant/chat_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/app_settings_config_widget.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_feed.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_item_view.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/permission_request/widgets/permission_card.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/prompt_composer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

Widget _item(
  ChatItem item, {
  Locale locale = const Locale('en'),
  Dependencies? dependencies,
  String? projectRoot,
  double? width,
  ValueChanged<String>? onOpenChange,
}) => testApp(
  Align(
    alignment: Alignment.topCenter,
    child: SizedBox(
      width: width,
      child: SingleChildScrollView(
        child: ChatItemView(
          item: item,
          onAnswerPermission: (_, _) {},
          projectRoot: projectRoot,
          onOpenChange: onOpenChange,
        ),
      ),
    ),
  ),
  locale: locale,
  dependencies: dependencies,
);

/// Plain text of the rich text whose text contains [part].
String _richText(WidgetTester tester, String part) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((w) => w.text.toPlainText())
    .singleWhere((t) => t.contains(part));

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

  group('clicking an edit row', () {
    const edit = ToolCallItem(
      0,
      toolCallId: 't',
      title: 'Edit a.dart',
      kind: 'edit',
      status: 'completed',
      content: <ToolContent>[ToolDiffContent(path: '/p/lib/a.dart', oldText: 'a', newText: 'b')],
    );

    testWidgets('opens the change; the chevron expands the body instead', (tester) async {
      useDesktopView(tester);
      final opened = <String>[];
      await tester.pumpWidget(_item(edit, onOpenChange: opened.add));
      expect(find.byType(DiffView), findsOneWidget);

      await tester.tap(find.byTooltip('Open in Changes'));
      await tester.pump();
      expect(opened, <String>['/p/lib/a.dart']);
      expect(find.byType(DiffView), findsOneWidget);

      await tester.tap(find.byTooltip('Hide details'));
      await tester.pump();
      expect(opened, hasLength(1));
      expect(find.byType(DiffView), findsNothing);
      expect(find.byTooltip('Show details'), findsOneWidget);
    });

    testWidgets('an agent path relative to the project opens the absolute, normalized one', (
      tester,
    ) async {
      useDesktopView(tester);
      final opened = <String>[];
      await tester.pumpWidget(
        _item(
          const ToolCallItem(
            0,
            toolCallId: 't',
            title: 'Edit a.dart',
            kind: 'edit',
            status: 'completed',
            content: <ToolContent>[
              ToolDiffContent(path: 'lib/./sub/../a.dart', oldText: 'a', newText: 'b'),
            ],
          ),
          projectRoot: '/p',
          onOpenChange: opened.add,
        ),
      );

      await tester.tap(find.byTooltip('Open in Changes'));
      await tester.pump();

      expect(opened, <String>['/p/lib/a.dart']);
    });

    testWidgets('without a listener the header still expands the body', (tester) async {
      useDesktopView(tester);
      await tester.pumpWidget(_item(edit));
      expect(find.byTooltip('Hide details'), findsNothing);

      await tester.tap(find.text('Edit a.dart', findRichText: true));
      await tester.pump();

      expect(find.byType(DiffView), findsNothing);
    });

    testWidgets('a call without diffs keeps the header as the expander', (tester) async {
      useDesktopView(tester);
      final opened = <String>[];
      await tester.pumpWidget(
        _item(
          const ToolCallItem(
            0,
            toolCallId: 't',
            title: 'Run ls',
            kind: 'execute',
            status: 'completed',
            rawOutput: 'out',
          ),
          onOpenChange: opened.add,
        ),
      );
      expect(find.byTooltip('Open in Changes'), findsNothing);
      expect(find.text('out'), findsNothing);

      await tester.tap(find.text('Run ls', findRichText: true));
      await tester.pump();

      expect(find.text('out', findRichText: true), findsOneWidget);
      expect(opened, isEmpty);
    });
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
  });

  group('tool row path', () {
    const root = '/private/var/folders/xx/T/flutter_code_agent_project';
    const deep = '$root/lib/src/feature/booking/widgets/screens/hello.txt';

    ToolCallItem write({String title = 'Write $deep'}) => ToolCallItem(
      0,
      toolCallId: 't',
      title: title,
      kind: 'edit',
      status: 'completed',
      locations: const <String>[deep],
    );

    testWidgets('shows the file name and the folder relative to the project, once', (tester) async {
      useDesktopView(tester);
      await tester.pumpWidget(_item(write(), projectRoot: root));

      expect(
        _richText(tester, 'hello.txt'),
        'Write hello.txt lib/src/feature/booking/widgets/screens/',
      );
      expect(find.textContaining('/private/var', findRichText: true), findsNothing);
    });

    testWidgets('the file name stays whole when the row is narrow, the folder gives way', (
      tester,
    ) async {
      useDesktopView(tester);
      await tester.pumpWidget(_item(write(), projectRoot: root, width: 280));

      final paragraph = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('hello.txt')),
      );
      expect(paragraph.didExceedMaxLines, isTrue);
      final text = paragraph.text.toPlainText();
      final start = text.indexOf('hello.txt');
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + 'hello.txt'.length),
      );
      expect(boxes, isNotEmpty);
      final nameWidth = boxes.last.right - boxes.first.left;
      TextStyle? nameStyle;
      paragraph.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'hello.txt') nameStyle = span.style;
        return true;
      });
      final probe = TextPainter(
        text: TextSpan(text: 'hello.txt', style: nameStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(nameWidth, greaterThanOrEqualTo(probe.width));
    });

    testWidgets('a title without a path keeps its text', (tester) async {
      useDesktopView(tester);
      await tester.pumpWidget(
        _item(
          const ToolCallItem(0, toolCallId: 't', title: 'Run flutter test', kind: 'execute'),
          projectRoot: root,
        ),
      );

      expect(find.text('Run flutter test', findRichText: true), findsOneWidget);
    });

    testWidgets('a title that is only the path shows just the file', (tester) async {
      useDesktopView(tester);
      await tester.pumpWidget(_item(write(title: deep), projectRoot: root));

      expect(_richText(tester, 'hello.txt'), 'hello.txt lib/src/feature/booking/widgets/screens/');
    });
  });

  testWidgets('compact density tightens the feed', (tester) async {
    useDesktopView(tester);
    final dependencies = testDependencies();
    await tester.pumpWidget(
      testApp(
        ChatFeed(
          items: const <ChatItem>[AgentMessageItem(0, text: 'hello')],
          onAnswerPermission: (_, _) {},
        ),
        dependencies: dependencies,
        withSettings: true,
      ),
    );
    await tester.pump();

    double rowPadding() =>
        tester
            .widget<Padding>(
              find.ancestor(of: find.byType(ChatItemView), matching: find.byType(Padding)).first,
            )
            .padding
            .vertical /
        2;

    expect(rowPadding(), 6);

    AppSettingsConfigInhWidget.of(tester.element(find.byType(ChatFeed))).controller
        .update((current) => current.copyWith(feedDensity: FeedDensity.compact));
    await tester.pumpAndSettle();
    expect(rowPadding(), 2);
    await disposeTestApp(tester, dependencies);
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

  testWidgets('a read group shows paths relative to the project', (tester) async {
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
          projectRoot: '/p',
        ),
      ),
    );

    expect(_richText(tester, 'f0.dart'), 'f0.dart lib/');

    await tester.tap(find.text('Read 3 files'));
    await tester.pumpAndSettle();

    expect(find.text('lib/f1.dart'), findsOneWidget);
    expect(find.text('lib/f2.dart'), findsOneWidget);
    expect(find.text('/p/lib/f1.dart'), findsNothing);
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

    expect(tester.getSize(find.byType(ChatItemView)).width, kChatColumnWidth);
  });

  testWidgets('the feed item lines up with the composer box', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      testApp(
        Column(
          children: <Widget>[
            Expanded(
              child: ChatFeed(
                items: <ChatItem>[AgentMessageItem(0, text: 'word ' * 400)],
                onAnswerPermission: (_, _) {},
              ),
            ),
            PromptComposer(
              controller: TextEditingController(),
              focusNode: FocusNode(),
              canSend: true,
              canStop: false,
              onSend: () {},
              onStop: () {},
            ),
          ],
        ),
      ),
    );

    final item = tester.getRect(find.byType(ChatItemView));
    final box = tester.getRect(
      find.ancestor(of: find.byType(TextField), matching: find.byType(DecoratedBox)).last,
    );
    expect(item.width, box.width);
    expect(item.left, box.left);
  });

  testWidgets('only the latest pending permission card shows the key hints', (tester) async {
    useDesktopView(tester);
    PermissionItem request(int seq) => PermissionItem(
      seq,
      requestId: 'r$seq',
      title: 'Run $seq',
      command: 'ls $seq',
      options: const <PermissionOptionView>[
        PermissionOptionView(optionId: 'ok', name: 'Allow', kind: 'allow_once'),
        PermissionOptionView(optionId: 'no', name: 'Reject', kind: 'reject_once'),
      ],
    );
    await tester.pumpWidget(
      testApp(
        ChatFeed(
          items: <ChatItem>[request(0), request(1)],
          onAnswerPermission: (_, _) {},
          keyboardRequestId: 'r1',
        ),
      ),
    );

    expect(find.text('↵'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is PermissionCard && w.item.requestId == 'r1'),
        matching: find.text('↵'),
      ),
      findsOneWidget,
    );
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
