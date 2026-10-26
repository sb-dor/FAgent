import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/prompt_composer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  late TextEditingController text;
  late FocusNode focus;

  setUp(() {
    text = TextEditingController();
    focus = FocusNode();
  });

  tearDown(() {
    text.dispose();
    focus.dispose();
  });

  Widget composer({
    required bool canSend,
    required bool canStop,
    VoidCallback? onSend,
    VoidCallback? onStop,
  }) => testApp(
    PromptComposer(
      controller: text,
      focusNode: focus,
      canSend: canSend,
      canStop: canStop,
      onSend: onSend ?? () {},
      onStop: onStop ?? () {},
    ),
  );

  testWidgets('Enter sends, Shift+Enter does not', (tester) async {
    var sent = 0;
    await tester.pumpWidget(composer(canSend: true, canStop: false, onSend: () => sent++));
    await tester.enterText(find.byType(TextField), 'hello');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(sent, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sent, 1);
  });

  testWidgets('the send button is off for empty text or a busy chat', (tester) async {
    await tester.pumpWidget(composer(canSend: true, canStop: false));
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNotNull);

    await tester.pumpWidget(composer(canSend: false, canStop: false));
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
  });

  testWidgets('during a turn the button stops it', (tester) async {
    var stopped = false;
    await tester.pumpWidget(composer(canSend: false, canStop: true, onStop: () => stopped = true));
    await tester.tap(find.byTooltip('Stop'));
    expect(stopped, isTrue);
  });
}
