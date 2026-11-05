import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/project_rules/models/project_rule.dart';
import 'package:flutter_code_agent/src/feature/project_rules/widgets/project_rules_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  const rules = <ProjectRule>[
    ProjectRule(id: 'rule:builtin:a', name: 'architecture', description: 'Layout.', enabled: true),
    ProjectRule(id: 'rule:builtin:b', name: 'widgets', description: 'Widgets.', enabled: false),
  ];

  /// Opens the dialog and returns the future of its answer.
  Future<Future<List<ProjectRule>?>> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    bool dark = false,
    Size size = const Size(1280, 800),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Future<List<ProjectRule>?> answer;
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => answer = ProjectRulesDialog.show(context, rules),
            child: const Text('open'),
          ),
        ),
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answer;
  }

  bool checked(WidgetTester tester, String name) =>
      tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, name)).value!;

  ButtonStyleButton add(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(find.widgetWithText(FilledButton, 'Add'));

  testWidgets('enabled rules start checked; unchecking all disables Add', (tester) async {
    await open(tester);

    expect(find.text('Add the project rules?'), findsOneWidget);
    expect(find.text('Layout.'), findsOneWidget);
    expect(checked(tester, 'architecture'), isTrue);
    expect(checked(tester, 'widgets'), isFalse);
    expect(add(tester).onPressed, isNotNull);

    await tester.tap(find.text('architecture'));
    await tester.pump();

    expect(checked(tester, 'architecture'), isFalse);
    expect(add(tester).onPressed, isNull);
  });

  testWidgets('Add returns the checked rules', (tester) async {
    final answer = await open(tester);
    await tester.tap(find.text('widgets'));
    await tester.pump();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(await answer, rules);
  });

  testWidgets('Not now returns null', (tester) async {
    final answer = await open(tester);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(await answer, isNull);
  });

  for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
    for (final dark in <bool>[false, true]) {
      testWidgets('the dialog fits at 900×600 in ${locale.languageCode}, '
          '${dark ? 'dark' : 'light'}', (tester) async {
        await open(tester, locale: locale, dark: dark, size: const Size(900, 600));

        expect(find.byType(ProjectRulesDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
