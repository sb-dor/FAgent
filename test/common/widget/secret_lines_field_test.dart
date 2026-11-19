import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/widget/secret_lines_field.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  const notice = "Kept unencrypted in the app's database on this Mac.";

  group('maskSecretLines', () {
    test('keeps the key before the first separator', () {
      expect(maskSecretLines('A=1\nB=x=y\nC', '='), 'A=••••••\nB=••••••\n••••••');
    });

    test('keeps the space after the separator', () {
      expect(maskSecretLines('Authorization: Bearer t', ':'), 'Authorization: ••••••');
    });
  });

  Future<List<int>> pump(WidgetTester tester, TextEditingController controller) async {
    useDesktopView(tester);
    final edits = <int>[];
    await tester.pumpWidget(
      testApp(
        SecretLinesField(
          controller: controller,
          separator: '=',
          label: 'Env',
          onChanged: () => edits.add(edits.length),
        ),
      ),
    );
    return edits;
  }

  testWidgets('text starts hidden, Show reveals it for editing', (tester) async {
    final controller = TextEditingController(text: 'A=1\nB=secret');
    addTearDown(controller.dispose);
    final edits = await pump(tester, controller);

    expect(find.text('1'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('A=••••••\nB=••••••'), findsOneWidget);
    expect(find.text(notice), findsOneWidget);

    await tester.tap(find.byTooltip('Show'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('A=1\nB=secret'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'A=2');
    expect(controller.text, 'A=2');
    expect(edits, hasLength(1));
    expect(find.text(notice), findsOneWidget);

    await tester.tap(find.byTooltip('Hide'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('A=••••••'), findsOneWidget);
  });

  testWidgets('an empty controller starts shown', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pump(tester, controller);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Hide'), findsOneWidget);
    expect(find.text(notice), findsOneWidget);
  });
}
