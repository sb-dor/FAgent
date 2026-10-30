import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/widget/diff_view.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/permission_request/widgets/permission_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

PermissionItem _item({PermissionState state = PermissionState.pending, String? selected}) =>
    PermissionItem(
      0,
      requestId: 'claude#1#7',
      title: 'Run flutter test',
      command: 'flutter test',
      options: const <PermissionOptionView>[
        PermissionOptionView(optionId: 'allow-once', name: 'Yes', kind: 'allow_once'),
        PermissionOptionView(optionId: 'reject', name: 'No', kind: 'reject_once'),
      ],
      state: state,
      selectedOptionId: selected,
    );

PermissionItem _full({String? command, List<ToolDiffContent> diffs = const <ToolDiffContent>[]}) =>
    PermissionItem(
      0,
      requestId: 'claude#1#8',
      title: 'Agent wording',
      command: command,
      diffs: diffs,
      options: const <PermissionOptionView>[
        PermissionOptionView(
          optionId: 'always',
          name: 'Always in this project',
          kind: 'allow_always',
        ),
        PermissionOptionView(optionId: 'once', name: 'Allow', kind: 'allow_once'),
        PermissionOptionView(optionId: 'no', name: 'Reject', kind: 'reject_once'),
        PermissionOptionView(optionId: 'never', name: 'Never', kind: 'reject_always'),
      ],
    );

void main() {
  testWidgets('a command request asks to run the command', (tester) async {
    final answers = <String>[];
    await tester.pumpWidget(
      testApp(
        PermissionCard(
          item: _full(command: 'dart run build_runner build'),
          onAnswer: answers.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Run this command?'), findsOneWidget);
    expect(find.text('Agent wording'), findsNothing);
    final block = tester.widget<EditableText>(
      find.descendant(of: find.byType(SelectableText), matching: find.byType(EditableText)),
    );
    expect(block.style.fontFamily, contains('JetBrainsMono'));

    // Order: allow once, allow always, reject once, other options.
    final buttons = tester.widgetList<ButtonStyleButton>(
      find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(buttons.map((b) => b.runtimeType.toString()), <String>[
      'FilledButton',
      'OutlinedButton',
      'OutlinedButton',
      'TextButton',
    ]);
    expect(
      tester.getTopLeft(find.widgetWithText(FilledButton, 'Allow')).dx,
      lessThan(tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Always in this project')).dx),
    );
    expect(
      tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Always in this project')).dx,
      lessThan(tester.getTopLeft(find.widgetWithText(OutlinedButton, 'Reject')).dx),
    );
    expect(
      find.descendant(of: find.byType(FilledButton), matching: find.text('↵')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(OutlinedButton, 'Reject'),
        matching: find.text('Esc'),
      ),
      findsOneWidget,
    );
    expect(find.text('↵'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Never'));
    expect(answers, <String>['never']);
  });

  testWidgets('an edit request asks to apply the edits', (tester) async {
    await tester.pumpWidget(
      testApp(
        PermissionCard(
          item: _full(
            diffs: const <ToolDiffContent>[
              ToolDiffContent(path: 'lib/a.dart', oldText: 'a', newText: 'b'),
            ],
          ),
          onAnswer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apply these edits?'), findsOneWidget);
    expect(find.byType(DiffView), findsOneWidget);
  });

  testWidgets('a request without command or diff shows the agent title', (tester) async {
    await tester.pumpWidget(testApp(PermissionCard(item: _full(), onAnswer: (_) {})));
    await tester.pumpAndSettle();

    expect(find.text('Agent wording'), findsOneWidget);
  });

  testWidgets('reject and say declines through its own callback', (tester) async {
    var said = 0;
    final answers = <String>[];
    await tester.pumpWidget(
      testApp(
        PermissionCard(
          item: _full(command: 'ls'),
          onAnswer: answers.add,
          onRejectAndSay: () => said++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Reject and say…'));
    expect(said, 1);
    expect(answers, isEmpty);
  });

  testWidgets('without the callback there is no reject and say', (tester) async {
    await tester.pumpWidget(
      testApp(
        PermissionCard(
          item: _full(command: 'ls'),
          onAnswer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reject and say…'), findsNothing);
  });

  testWidgets('an answered request has no reject and say', (tester) async {
    await tester.pumpWidget(
      testApp(
        PermissionCard(
          item: _item(state: PermissionState.selected, selected: 'reject'),
          onAnswer: (_) {},
          onRejectAndSay: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reject and say…'), findsNothing);
  });

  testWidgets('a pending request offers the agent options', (tester) async {
    final answers = <String>[];
    await tester.pumpWidget(testApp(PermissionCard(item: _item(), onAnswer: answers.add)));
    await tester.pumpAndSettle();

    expect(find.text(r'$ flutter test'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'No'));
    expect(answers, <String>['allow-once', 'reject']);
  });

  testWidgets('an answered request shows the decision and no buttons', (tester) async {
    await tester.pumpWidget(
      testApp(
        PermissionCard(
          item: _item(state: PermissionState.selected, selected: 'reject'),
          onAnswer: (_) {},
        ),
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Отклонено · No'), findsOneWidget);
  });

  testWidgets('a stale request explains why it cannot be answered', (tester) async {
    await tester.pumpWidget(
      testApp(
        PermissionCard(
          item: _item(state: PermissionState.stale),
          onAnswer: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Expired'), findsOneWidget);
  });
}
