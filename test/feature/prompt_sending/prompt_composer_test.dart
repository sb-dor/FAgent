import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/constant/chat_constants.dart';
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
    List<String>? mentionFiles,
    VoidCallback? onMentionStart,
    List<Widget> toolbar = const <Widget>[],
    VoidCallback? onCycleMode,
  }) => testApp(
    PromptComposer(
      controller: text,
      focusNode: focus,
      canSend: canSend,
      canStop: canStop,
      onSend: onSend ?? () {},
      onStop: onStop ?? () {},
      mentionFiles: mentionFiles,
      onMentionStart: onMentionStart,
      toolbar: toolbar,
      onCycleMode: onCycleMode,
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

  testWidgets('the toolbar sits under the text field next to the send button', (tester) async {
    await tester.pumpWidget(
      composer(canSend: true, canStop: false, toolbar: const <Widget>[Text('chips')]),
    );

    final field = tester.getRect(find.byType(TextField));
    final chips = tester.getRect(find.text('chips'));
    final send = tester.getRect(find.byType(IconButton));
    expect(chips.top, greaterThanOrEqualTo(field.bottom));
    expect(chips.left, lessThan(send.left));
    expect(send.top, greaterThanOrEqualTo(field.bottom));
  });

  testWidgets('the composer is the chat column: 720 px wide and centred', (tester) async {
    useDesktopView(tester);
    await tester.pumpWidget(composer(canSend: true, canStop: false));

    final box = tester.getRect(
      find.ancestor(of: find.byType(TextField), matching: find.byType(DecoratedBox)).last,
    );
    expect(box.width, kChatColumnWidth);
    expect(box.center.dx, 640);
  });

  testWidgets('the hint mentions files and commands', (tester) async {
    await tester.pumpWidget(composer(canSend: true, canStop: false));
    expect(find.text('Ask the agent… @ file · / skill or command'), findsOneWidget);
  });

  group('Shift+Tab', () {
    Future<void> shiftTab(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }

    testWidgets('cycles the mode and keeps the focus in the field', (tester) async {
      var cycled = 0;
      await tester.pumpWidget(
        composer(
          canSend: true,
          canStop: false,
          onCycleMode: () => cycled++,
          toolbar: <Widget>[TextButton(onPressed: () {}, child: const Text('chip'))],
        ),
      );
      await tester.enterText(find.byType(TextField), 'hello');

      await shiftTab(tester);

      expect(cycled, 1);
      expect(focus.hasFocus, isTrue);
      expect(text.text, 'hello');
    });

    testWidgets('does nothing without a mode to cycle', (tester) async {
      await tester.pumpWidget(composer(canSend: true, canStop: false));
      await shiftTab(tester);
      expect(text.text, isEmpty);
    });

    testWidgets('a plain Tab does not cycle the mode', (tester) async {
      var cycled = 0;
      await tester.pumpWidget(composer(canSend: true, canStop: false, onCycleMode: () => cycled++));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(cycled, 0);
    });

    testWidgets('inside the file list Tab still inserts the file', (tester) async {
      var cycled = 0;
      await tester.pumpWidget(
        composer(
          canSend: true,
          canStop: false,
          onCycleMode: () => cycled++,
          mentionFiles: const <String>['pubspec.yaml'],
        ),
      );
      await tester.enterText(find.byType(TextField), '@pub');
      await tester.pump();

      await shiftTab(tester);

      expect(cycled, 0);
      expect(text.text, '@pubspec.yaml ');
    });
  });

  group('@ mentions', () {
    const files = <String>[
      'lib/main.dart',
      'lib/src/app.dart',
      'pubspec.yaml',
      'test/app_test.dart',
    ];

    testWidgets('typing @ suggests files, arrows choose and Enter inserts', (tester) async {
      var started = 0;
      var sent = 0;
      await tester.pumpWidget(
        composer(
          canSend: true,
          canStop: false,
          onSend: () => sent++,
          mentionFiles: files,
          onMentionStart: () => started++,
        ),
      );
      await tester.enterText(find.byType(TextField), 'look at @app');
      await tester.pump();

      expect(started, 1);
      expect(find.text('app.dart'), findsOneWidget);
      expect(find.text('app_test.dart'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sent, 0);
      expect(text.text, 'look at @test/app_test.dart ');
      expect(find.text('app.dart'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
    });

    testWidgets('Escape closes the list and Enter sends again', (tester) async {
      var sent = 0;
      await tester.pumpWidget(
        composer(canSend: true, canStop: false, onSend: () => sent++, mentionFiles: files),
      );
      await tester.enterText(find.byType(TextField), '@pub');
      await tester.pump();
      expect(find.text('pubspec.yaml'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('pubspec.yaml'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
    });

    testWidgets('suggestions appear when the file list arrives', (tester) async {
      await tester.pumpWidget(
        composer(canSend: true, canStop: false, mentionFiles: const <String>[]),
      );
      await tester.enterText(find.byType(TextField), '@main');
      await tester.pump();
      expect(find.text('main.dart'), findsNothing);

      await tester.pumpWidget(composer(canSend: true, canStop: false, mentionFiles: files));
      expect(find.text('main.dart'), findsOneWidget);
    });

    testWidgets('clicking a suggestion inserts it and keeps the caret', (tester) async {
      await tester.pumpWidget(composer(canSend: true, canStop: false, mentionFiles: files));
      await tester.enterText(find.byType(TextField), '@main');
      await tester.pump();

      await tester.tap(find.text('main.dart'), kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(text.text, '@lib/main.dart ');
      expect(focus.hasFocus, isTrue);
    });

    testWidgets('an e-mail address is not a mention', (tester) async {
      await tester.pumpWidget(composer(canSend: true, canStop: false, mentionFiles: files));
      await tester.enterText(find.byType(TextField), 'mail me@app');
      await tester.pump();
      expect(find.text('app.dart'), findsNothing);
    });
  });
}
