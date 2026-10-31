import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_config_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_arguments_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_run_config_repository.dart';
import '../../support/test_app.dart';

void main() {
  late MemoryRunConfigRepository repository;
  late RunConfigController controller;

  setUp(() {
    repository = MemoryRunConfigRepository();
    controller = RunConfigController(repository: repository);
  });
  tearDown(() => controller.dispose());

  Future<void> openDialog(
    WidgetTester tester, {
    RunArguments initial = const RunArguments(),
    Locale locale = const Locale('en'),
  }) async {
    useDesktopView(tester);
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => RunArgumentsDialog.show(
              context,
              projectId: 1,
              arguments: initial,
              controller: controller,
            ),
            child: const Text('open'),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(String id) => find.byKey(ValueKey<String>('run-arguments-$id'));

  Finder saveButton() => find.widgetWithText(FilledButton, 'Save');

  testWidgets('shows the saved arguments, one define per line', (tester) async {
    await openDialog(
      tester,
      initial: const RunArguments(
        flavor: 'dev',
        dartDefines: <String>['A=1', 'B=2'],
        extraArgs: '--verbose',
      ),
    );

    expect(find.text('Run arguments'), findsOneWidget);
    expect(tester.widget<TextField>(field('flavor')).controller!.text, 'dev');
    expect(tester.widget<TextField>(field('defines')).controller!.text, 'A=1\nB=2');
    expect(tester.widget<TextField>(field('extra')).controller!.text, '--verbose');
    expect(tester.getSize(find.byKey(const ValueKey<String>('run-arguments-content'))).width, 480);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a reserved flag shows the error and disables Save; fixing it saves', (tester) async {
    await openDialog(tester);

    await tester.enterText(field('extra'), '--release');
    await tester.pump();
    expect(find.textContaining('sets this flag itself'), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);

    await tester.enterText(field('extra'), '--verbose');
    await tester.pump();
    expect(find.textContaining('sets this flag itself'), findsNothing);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull);

    await tester.enterText(field('flavor'), ' dev ');
    await tester.enterText(field('defines'), 'API=https://dev\n\n  DEBUG=1  \n');
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.$1, 1);
    expect(
      repository.saved.single.$2,
      const RunArguments(
        flavor: 'dev',
        dartDefines: <String>['API=https://dev', 'DEBUG=1'],
        extraArgs: '--verbose',
      ),
    );
    expect(find.byType(AlertDialog), findsNothing, reason: 'closes once saved');
  });

  testWidgets('a define without "=" and an unclosed quote are explained under their fields', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.enterText(field('defines'), 'KEY');
    await tester.pump();
    expect(find.textContaining('KEY=VALUE'), findsWidgets);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);

    await tester.enterText(field('defines'), 'KEY=1');
    await tester.enterText(field('extra'), '"x');
    await tester.pump();
    expect(find.textContaining('quote'), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('clearing the fields saves the default arguments', (tester) async {
    await openDialog(tester, initial: const RunArguments(flavor: 'dev'));

    await tester.enterText(field('flavor'), '');
    await tester.pump();
    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(repository.saved.single.$2, const RunArguments());
  });

  testWidgets('Escape closes the dialog without saving', (tester) async {
    await openDialog(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.saved, isEmpty);
  });

  testWidgets('Cancel closes without saving', (tester) async {
    await openDialog(tester);
    await tester.enterText(field('flavor'), 'dev');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.saved, isEmpty);
  });

  testWidgets('a failed save keeps the dialog open and says so', (tester) async {
    repository.saveError = Exception('disk full');
    await openDialog(tester);
    await tester.enterText(field('flavor'), 'dev');
    await tester.pump();

    await tester.tap(saveButton());
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Could not save'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('speaks Russian', (tester) async {
    await openDialog(tester, locale: const Locale('ru'));
    expect(find.text('Аргументы запуска'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
