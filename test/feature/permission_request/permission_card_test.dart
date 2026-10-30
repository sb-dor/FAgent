import 'package:flutter/material.dart';
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

void main() {
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
