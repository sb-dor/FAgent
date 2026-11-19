import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/tool_call_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  testWidgets('long output is cut by characters, never inside an emoji', (tester) async {
    useDesktopView(tester);
    final output = '${'a' * 3999}👍🏽 and the rest of the output';
    await tester.pumpWidget(
      testApp(
        SingleChildScrollView(
          child: ToolCallCard(
            call: ToolCallItem(
              0,
              toolCallId: 't',
              title: 'Run ls',
              kind: 'execute',
              status: 'completed',
              rawOutput: output,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Run ls', findRichText: true));
    await tester.pump();

    final expected = '${'a' * 3999}👍🏽…';
    expect(find.text(expected, findRichText: true), findsOneWidget);
    expect(expected.characters.length, 4001);
  });

  testWidgets('output with more code units than the limit but fewer characters is not cut', (
    tester,
  ) async {
    useDesktopView(tester);
    final output = '👍🏽' * 1500;
    expect(output.length, greaterThan(4000));
    await tester.pumpWidget(
      testApp(
        SingleChildScrollView(
          child: ToolCallCard(
            call: ToolCallItem(
              0,
              toolCallId: 't',
              title: 'Run ls',
              kind: 'execute',
              status: 'completed',
              rawOutput: output,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Run ls', findRichText: true));
    await tester.pump();

    expect(find.text(output, findRichText: true), findsOneWidget);
  });
}
