import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/constant/chat_constants.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/command_suggestions.dart';
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
    List<SlashCommand> commands = const <SlashCommand>[],
    VoidCallback? onAcceptPending,
    VoidCallback? onRejectPending,
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
      commands: commands,
      onAcceptPending: onAcceptPending,
      onRejectPending: onRejectPending,
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

  group('pending permission', () {
    testWidgets('with an empty composer Enter allows and Escape rejects', (tester) async {
      var accepted = 0;
      var rejected = 0;
      var sent = 0;
      await tester.pumpWidget(
        composer(
          canSend: false,
          canStop: true,
          onSend: () => sent++,
          onAcceptPending: () => accepted++,
          onRejectPending: () => rejected++,
        ),
      );
      await tester.tap(find.byType(TextField));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((accepted, rejected, sent), (1, 0, 0));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect((accepted, rejected, sent), (1, 1, 0));
    });

    testWidgets('with a draft in the composer Enter and Escape do not answer', (tester) async {
      var accepted = 0;
      var rejected = 0;
      var sent = 0;
      await tester.pumpWidget(
        composer(
          canSend: true,
          canStop: false,
          onSend: () => sent++,
          onAcceptPending: () => accepted++,
          onRejectPending: () => rejected++,
        ),
      );
      await tester.enterText(find.byType(TextField), 'wait, first');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);

      expect((accepted, rejected), (0, 0));
      expect(sent, 1);
    });

    testWidgets('Shift+Enter does not allow', (tester) async {
      var accepted = 0;
      await tester.pumpWidget(
        composer(canSend: false, canStop: true, onAcceptPending: () => accepted++),
      );
      await tester.tap(find.byType(TextField));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(accepted, 0);
    });

    testWidgets('an open suggestion list takes Escape and Enter first', (tester) async {
      var accepted = 0;
      var rejected = 0;
      await tester.pumpWidget(
        composer(
          canSend: false,
          canStop: true,
          mentionFiles: const <String>['lib/main.dart'],
          onAcceptPending: () => accepted++,
          onRejectPending: () => rejected++,
        ),
      );
      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(rejected, 0);

      // The list is closed and the field holds a draft: still nothing is answered.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect((accepted, rejected), (0, 0));
    });

    testWidgets('without a pending request Enter and Escape behave as before', (tester) async {
      var sent = 0;
      await tester.pumpWidget(composer(canSend: true, canStop: false, onSend: () => sent++));
      await tester.tap(find.byType(TextField));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);

      expect(sent, 1);
    });
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

    testWidgets('an equal file list from a rebuild keeps the highlighted file', (tester) async {
      await tester.pumpWidget(composer(canSend: true, canStop: false, mentionFiles: files));
      await tester.enterText(find.byType(TextField), '@app');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      await tester.pumpWidget(
        composer(canSend: true, canStop: false, mentionFiles: <String>[...files]),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(text.text, '@test/app_test.dart ');
    });

    testWidgets('an e-mail address is not a mention', (tester) async {
      await tester.pumpWidget(composer(canSend: true, canStop: false, mentionFiles: files));
      await tester.enterText(find.byType(TextField), 'mail me@app');
      await tester.pump();
      expect(find.text('app.dart'), findsNothing);
    });
  });

  group('/ commands', () {
    const commands = <SlashCommand>[
      SlashCommand(name: 'compact', description: 'Compact the chat', source: SlashSource.agent),
      SlashCommand(name: 'init', description: 'Write AGENTS.md', source: SlashSource.agent),
      SlashCommand(name: 'review', source: SlashSource.agent),
    ];

    Widget withCommands({VoidCallback? onSend}) =>
        composer(canSend: true, canStop: false, onSend: onSend, commands: commands);

    testWidgets('typing / at the start suggests commands and Enter inserts one', (tester) async {
      var sent = 0;
      await tester.pumpWidget(withCommands(onSend: () => sent++));
      await tester.enterText(find.byType(TextField), '/comp');
      await tester.pump();

      expect(find.text('/compact'), findsOneWidget);
      expect(find.text('Compact the chat'), findsOneWidget);
      expect(find.text('/init'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sent, 0);
      expect(text.text, '/compact ');
      expect(text.selection, const TextSelection.collapsed(offset: 9));
      expect(find.text('/compact'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
    });

    testWidgets('the list has an App and an Agent section', (tester) async {
      await tester.pumpWidget(withCommands());
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();

      expect(find.text('App'), findsOneWidget);
      expect(find.text('Agent'), findsOneWidget);
      expect(find.text('/run'), findsOneWidget);
      expect(find.text('/compact'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('/run')).dy,
        lessThan(tester.getTopLeft(find.text('/compact')).dy),
      );
    });

    testWidgets('an empty section is hidden', (tester) async {
      await tester.pumpWidget(withCommands());
      await tester.enterText(find.byType(TextField), '/comp');
      await tester.pump();

      expect(find.text('App'), findsNothing);
      expect(find.text('Agent'), findsOneWidget);
    });

    testWidgets('arrows choose among the enabled commands, Tab inserts', (tester) async {
      await tester.pumpWidget(withCommands());
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(text.text, '/init ');
    });

    testWidgets('a / in the middle of text is not a command', (tester) async {
      await tester.pumpWidget(withCommands());
      await tester.enterText(find.byType(TextField), 'try /comp');
      await tester.pump();
      expect(find.text('/compact'), findsNothing);

      await tester.enterText(find.byType(TextField), '/compact now');
      await tester.pump();
      expect(find.text('/compact'), findsNothing);
    });

    testWidgets('app commands are shown but not inserted', (tester) async {
      var sent = 0;
      // The field itself also shows the typed `/run`.
      final row = find.descendant(of: find.byType(CommandSuggestions), matching: find.text('/run'));
      await tester.pumpWidget(withCommands(onSend: () => sent++));
      await tester.enterText(find.byType(TextField), '/run');
      await tester.pump();

      expect(row, findsOneWidget);
      expect(find.text('Coming in M2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.tap(row, kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(text.text, '/run');
      expect(sent, 0);
      expect(row, findsOneWidget);
    });

    testWidgets('Escape closes the list for this /, a new one reopens it', (tester) async {
      var sent = 0;
      await tester.pumpWidget(withCommands(onSend: () => sent++));
      await tester.enterText(find.byType(TextField), '/co');
      await tester.pump();
      expect(find.text('/compact'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('/compact'), findsNothing);
      await tester.enterText(find.byType(TextField), '/com');
      await tester.pump();
      expect(find.text('/compact'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.enterText(find.byType(TextField), '/co');
      await tester.pump();
      expect(find.text('/compact'), findsOneWidget);
    });

    testWidgets('clicking a command inserts it and keeps the caret', (tester) async {
      await tester.pumpWidget(withCommands());
      await tester.enterText(find.byType(TextField), '/rev');
      await tester.pump();

      await tester.tap(find.text('/review'), kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(text.text, '/review ');
      expect(focus.hasFocus, isTrue);
    });

    testWidgets('without matches Enter sends the text', (tester) async {
      var sent = 0;
      await tester.pumpWidget(withCommands(onSend: () => sent++));
      await tester.enterText(find.byType(TextField), '/zzz');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
    });

    testWidgets('new commands from the agent show up in an open list', (tester) async {
      await tester.pumpWidget(composer(canSend: true, canStop: false));
      await tester.enterText(find.byType(TextField), '/comp');
      await tester.pump();
      expect(find.text('/compact'), findsNothing);

      await tester.pumpWidget(withCommands());
      expect(find.text('/compact'), findsOneWidget);
    });

    testWidgets('an equal list from a rebuild keeps the highlighted command', (tester) async {
      await tester.pumpWidget(composer(canSend: true, canStop: false, commands: commands));
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      await tester.pumpWidget(
        composer(canSend: true, canStop: false, commands: <SlashCommand>[...commands]),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(text.text, '/init ');
    });

    testWidgets('new commands keep the highlight on the command that is still listed', (
      tester,
    ) async {
      await tester.pumpWidget(composer(canSend: true, canStop: false, commands: commands));
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      await tester.pumpWidget(
        composer(
          canSend: true,
          canStop: false,
          commands: <SlashCommand>[
            const SlashCommand(name: 'aaa', source: SlashSource.agent),
            ...commands,
          ],
        ),
      );
      expect(find.text('/aaa'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(text.text, '/init ');
    });

    testWidgets('@ mentions still work next to commands', (tester) async {
      await tester.pumpWidget(
        composer(
          canSend: true,
          canStop: false,
          commands: commands,
          mentionFiles: const <String>['pubspec.yaml'],
        ),
      );
      await tester.enterText(find.byType(TextField), '/compact @pub');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(text.text, '/compact @pubspec.yaml ');
    });
  });
}
