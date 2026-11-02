import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/custom_agent_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

Finder _field(String id) => find.byKey(ValueKey<String>('custom-agent-$id'));

void main() {
  /// Opens the dialog (with [initial]) from a button; [result] gets what it returned.
  Future<List<CustomAgentDraft?>> open(
    WidgetTester tester, {
    CustomAgentDraft? initial,
    Locale locale = const Locale('en'),
  }) async {
    useDesktopView(tester);
    final results = <CustomAgentDraft?>[];
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                results.add(await CustomAgentDialog.show(context, initial: initial)),
            child: const Text('open'),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  FilledButton addButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'));

  testWidgets('name and command are required', (tester) async {
    await open(tester);

    expect(find.text('Add ACP agent'), findsOneWidget);
    expect(addButton(tester).onPressed, isNull);
    await tester.enterText(_field('name'), 'Mine');
    await tester.pump();
    expect(addButton(tester).onPressed, isNull);
    await tester.enterText(_field('command'), '   ');
    await tester.pump();
    expect(addButton(tester).onPressed, isNull);
    await tester.enterText(_field('command'), 'mine');
    await tester.pump();
    expect(addButton(tester).onPressed, isNotNull);
  });

  testWidgets('returns the draft: arguments one per line, KEY=value lines', (tester) async {
    final results = await open(tester);

    await tester.enterText(_field('name'), '  Mine  ');
    await tester.enterText(_field('command'), ' /opt/mine/bin/agent ');
    await tester.enterText(_field('arguments'), '--acp\n\n  --model fast  \n');
    await tester.enterText(_field('environment'), 'A=1\n\n B = two words \nURL=http://x?a=b');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(
      results.single,
      const CustomAgentDraft(
        name: 'Mine',
        executable: '/opt/mine/bin/agent',
        arguments: <String>['--acp', '--model fast'],
        environment: <String, String>{'A': '1', 'B': 'two words', 'URL': 'http://x?a=b'},
      ),
    );
    expect(find.text('Add ACP agent'), findsNothing);
  });

  testWidgets('a line without KEY=value is explained and the dialog stays', (tester) async {
    final results = await open(tester);

    await tester.enterText(_field('name'), 'Mine');
    await tester.enterText(_field('command'), 'mine');
    await tester.enterText(_field('environment'), 'A=1\noops');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Write every line as KEY=value.'), findsOneWidget);
    expect(find.text('Add ACP agent'), findsOneWidget);
    expect(results, isEmpty);

    // Editing the field forgets the explanation; a key without a value is fine.
    await tester.enterText(_field('environment'), 'A=1\n=x');
    await tester.pumpAndSettle();
    expect(find.text('Write every line as KEY=value.'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Write every line as KEY=value.'), findsOneWidget);

    await tester.enterText(_field('environment'), 'A=');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(results.single!.environment, <String, String>{'A': ''});
  });

  testWidgets('an environment key that is not a variable name is refused', (tester) async {
    final results = await open(tester);

    await tester.enterText(_field('name'), 'Mine');
    await tester.enterText(_field('command'), 'mine');
    await tester.enterText(_field('environment'), 'GOOD_1=x\n1BAD=y');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Line 2: "1BAD" is not a variable name.'), findsOneWidget);
    expect(results, isEmpty);

    await tester.enterText(_field('environment'), 'GOOD_1=x\nMY-VAR=y');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Line 2: "MY-VAR" is not a variable name.'), findsOneWidget);

    await tester.enterText(_field('environment'), '_ok=x\nB2=y');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(results.single!.environment, <String, String>{'_ok': 'x', 'B2': 'y'});
  });

  testWidgets('a key given twice is refused', (tester) async {
    final results = await open(tester);

    await tester.enterText(_field('name'), 'Mine');
    await tester.enterText(_field('command'), 'mine');
    await tester.enterText(_field('environment'), 'A=1\nB=2\nA=3');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Line 3: "A" is already set.'), findsOneWidget);
    expect(find.text('Add ACP agent'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('the rules channel defaults to the first message and can be changed', (tester) async {
    final results = await open(tester);

    await tester.enterText(_field('name'), 'Mine');
    await tester.enterText(_field('command'), 'mine');
    await tester.tap(_field('rules'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System prompt').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(results.single!.rulesChannel, RulesChannel.systemPrompt);
  });

  testWidgets('cancel returns nothing', (tester) async {
    final results = await open(tester);

    await tester.enterText(_field('name'), 'Mine');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(results, <CustomAgentDraft?>[null]);
  });

  testWidgets('editing starts from the stored agent', (tester) async {
    final results = await open(
      tester,
      initial: const CustomAgentDraft(
        name: 'Mine',
        executable: 'mine',
        arguments: <String>['--acp', '--fast'],
        environment: <String, String>{'A': '1'},
        rulesChannel: RulesChannel.claudeMeta,
      ),
    );

    expect(find.text('Edit ACP agent'), findsOneWidget);
    expect(find.text('--acp\n--fast'), findsOneWidget);
    expect(find.text('A=1'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(results.single!.rulesChannel, RulesChannel.claudeMeta);
    expect(results.single!.arguments, <String>['--acp', '--fast']);
  });

  testWidgets('fits in Russian', (tester) async {
    await open(tester, locale: const Locale('ru'));

    expect(find.text('Добавить ACP-агента'), findsOneWidget);
    expect(find.text('Первое сообщение'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
