import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/creation_chip.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/creation_progress.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/new_project_dialog.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/flutter_version_runner.dart';
import '../../support/memory_project_creation_repository.dart';
import '../../support/test_app.dart';

const _nameField = ValueKey<String>('new-project-name');
const _step = Duration(milliseconds: 100);
const _stop = ValueKey<String>('creation-stop');
const _minimize = ValueKey<String>('creation-minimize');
const _close = ValueKey<String>('creation-close');
const _openProject = ValueKey<String>('creation-open-project');

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    tester.state<WorkspaceConfigWidgetState>(find.byType(WorkspaceConfigWidget));

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Lets [duration] of fake time pass in frames. `pumpAndSettle` never ends while a spinner turns.
Future<void> _elapse(WidgetTester tester, Duration duration) async {
  for (var left = duration; left > Duration.zero; left -= const Duration(milliseconds: 50)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A repository whose run prints [lines] in the first step.
final class _ChattyRepository implements IProjectCreationRepository {
  _ChattyRepository(this.lines);

  final List<String> lines;

  @override
  Future<String> defaultParent() async => '/Users/test/StudioProjects';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<CreationRun> create(NewProjectRequest request) async* {
    final kinds = creationStepsFor(request);
    yield CreationRun(
      steps: <CreationStep>[
        CreationStep(kind: kinds.first, status: CreationStepStatus.running, output: lines),
        for (final kind in kinds.skip(1)) CreationStep(kind: kind),
      ],
    );
    // Stays running until the controller is disposed.
    await Completer<void>().future;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late MemoryProjectCreationRepository memory;

  Future<void> pumpWindow(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    bool dark = false,
    Size size = const Size(1280, 800),
    IProjectCreationRepository? repository,
    bool withLongProject = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    memory = MemoryProjectCreationRepository(step: _step);
    dependencies = testDependencies(
      projectCreationRepository: repository ?? memory,
      flutterSdkRepository: FlutterSdkRepositoryImpl(
        which: (_) => '/opt/flutter/bin/flutter',
        runProcess: flutterVersionRunner,
        step: Duration.zero,
      ),
    );
    if (withLongProject) {
      final database = dependencies.database;
      await database
          .into(database.projectsTable)
          .insert(
            ProjectsTableCompanion.insert(
              path: '/work/a_project_with_a_really_long_name_that_does_not_fit_the_sidebar',
              name: 'a_project_with_a_really_long_name_that_does_not_fit_the_sidebar',
            ),
          );
    }
    await tester.pumpWidget(
      testApp(
        const WorkspaceConfigWidget(),
        dependencies: dependencies,
        withSettings: true,
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
      ),
    );
    await _settle(tester);
    await tester.pumpAndSettle();
  }

  /// Picks "New Flutter project…" in the "＋ Project" menu. The creation may be running, so it
  /// never waits for the app to settle.
  Future<void> openFromMenu(WidgetTester tester, {bool ru = false}) async {
    await tester.tap(find.text(ru ? 'Проект' : 'Project'));
    await _elapse(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text(ru ? 'Новый Flutter-проект…' : 'New Flutter project…'));
    await _elapse(tester, const Duration(milliseconds: 300));
  }

  /// Opens the form, types [name] and presses Create; the run starts.
  Future<void> startCreation(
    WidgetTester tester, {
    String name = 'avera_booking',
    bool ru = false,
  }) async {
    await openFromMenu(tester, ru: ru);
    await tester.enterText(find.byKey(_nameField), name);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('new-project-create')));
    await tester.pump();
  }

  Finder inProgress(Finder finder) =>
      find.descendant(of: find.byType(CreationProgress), matching: finder);

  Finder chip() => find.byKey(const ValueKey<String>('creation-chip'));

  Finder minimize(bool ru) => find.text(ru ? 'Свернуть' : 'Minimize');

  testWidgets('shows steps as they run', (tester) async {
    await pumpWindow(tester);
    await startCreation(tester);

    expect(find.text('Creating avera_booking'), findsOneWidget);
    expect(find.text('flutter create'), findsOneWidget);
    expect(find.text('git init'), findsOneWidget);
    expect(find.text('flutter analyze'), findsOneWidget);
    expect(find.text('First commit'), findsOneWidget);
    expect(inProgress(find.byType(CircularProgressIndicator)), findsNothing);
    expect(inProgress(find.text('○')), findsNWidgets(5));

    await _elapse(tester, _step);
    expect(inProgress(find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(inProgress(find.text('○')), findsNWidgets(4));

    await _elapse(tester, const Duration(milliseconds: 300));
    expect(inProgress(find.text('Wrote 130 files.')), findsOneWidget);
    expect(inProgress(find.text('✓')), findsOneWidget);
    expect(find.byKey(_close), findsNothing);

    await _elapse(tester, const Duration(seconds: 3));

    expect(inProgress(find.text('avera_booking: done')), findsOneWidget);
    expect(inProgress(find.text('✓')), findsNWidgets(5));
    expect(inProgress(find.byType(CircularProgressIndicator)), findsNothing);
    expect(inProgress(find.text('Architecture skeleton')), findsOneWidget);
    expect(find.text('✎ lib/src/common/localization/intl_en.arb'), findsOneWidget);
    expect(find.text('⌁ dart run build_runner build'), findsOneWidget);
    expect(find.text('No issues found!'), findsOneWidget);
    expect(find.text('6 s'), findsOneWidget);
    expect(find.text('Minimize'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('minimize keeps it running', (tester) async {
    await pumpWindow(tester);
    await startCreation(tester);

    await tester.tap(minimize(false));
    await _elapse(tester, const Duration(milliseconds: 300));

    expect(find.byType(NewProjectDialog), findsNothing);
    expect(chip(), findsOneWidget);
    expect(find.text('Creating avera_booking · 0/5'), findsOneWidget);

    await _elapse(tester, const Duration(milliseconds: 250));
    expect(find.text('Creating avera_booking · 1/5'), findsOneWidget);
    await _elapse(tester, const Duration(milliseconds: 250));
    expect(find.text('Creating avera_booking · 2/5'), findsOneWidget);

    await tester.tap(chip());
    await _elapse(tester, const Duration(milliseconds: 300));

    expect(find.byType(NewProjectDialog), findsOneWidget);
    expect(find.text('Creating avera_booking'), findsOneWidget);
    expect(find.byKey(_nameField), findsNothing);
    expect(memory.requests, hasLength(1));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('close and Esc keep it running too', (tester) async {
    await pumpWindow(tester);
    await startCreation(tester);

    await tester.tap(find.byTooltip('Close'));
    await _elapse(tester, const Duration(milliseconds: 300));
    expect(find.byType(NewProjectDialog), findsNothing);
    expect(chip(), findsOneWidget);

    await tester.tap(chip());
    await _elapse(tester, const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _elapse(tester, const Duration(milliseconds: 300));

    expect(find.byType(NewProjectDialog), findsNothing);
    expect(chip(), findsOneWidget);
    await _elapse(tester, const Duration(seconds: 3));
    expect(find.text('avera_booking: done'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('menu reopens the running creation', (tester) async {
    await pumpWindow(tester);
    await startCreation(tester);
    await _elapse(tester, _step);
    await tester.tap(minimize(false));
    await _elapse(tester, const Duration(milliseconds: 300));

    await openFromMenu(tester);

    expect(find.byType(NewProjectDialog), findsOneWidget);
    expect(find.text('Creating avera_booking'), findsOneWidget);
    expect(find.byKey(_nameField), findsNothing);
    expect(memory.requests, hasLength(1));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('menu reopens a finished creation on its result', (tester) async {
    await pumpWindow(tester);
    await startCreation(tester);
    await _elapse(tester, const Duration(seconds: 3));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await openFromMenu(tester);

    expect(inProgress(find.text('avera_booking: done')), findsOneWidget);
    expect(find.byKey(_nameField), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('close resets to a fresh form', (tester) async {
    await pumpWindow(tester);
    await startCreation(tester);
    await _elapse(tester, const Duration(seconds: 3));

    await tester.tap(find.byKey(_close));
    // The form must not flash while the dialog fades out.
    await tester.pump();
    expect(find.byKey(_nameField), findsNothing);
    await tester.pumpAndSettle();

    expect(find.byType(NewProjectDialog), findsNothing);
    expect(chip(), findsNothing);
    expect(_workspace(tester).projectCreation.state, isA<ProjectCreation$IdleState>());

    await openFromMenu(tester);
    await tester.pumpAndSettle();

    expect(find.text('New Flutter project'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(_nameField)).controller!.text, isEmpty);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('chip can be dismissed after completion', (tester) async {
    await pumpWindow(tester);
    await startCreation(tester);
    await tester.tap(minimize(false));
    await _elapse(tester, const Duration(seconds: 3));

    expect(find.text('avera_booking: done'), findsOneWidget);
    expect(find.byTooltip('Hide'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide'));
    await tester.pumpAndSettle();

    expect(chip(), findsNothing);
    expect(_workspace(tester).projectCreation.state, isA<ProjectCreation$IdleState>());
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a running chip has no hide button', (tester) async {
    await pumpWindow(tester);
    await startCreation(tester);
    await tester.tap(minimize(false));
    await _elapse(tester, const Duration(milliseconds: 300));

    expect(chip(), findsOneWidget);
    expect(find.byTooltip('Hide'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('running offers stop and minimize', (tester) async {
    await pumpWindow(tester);
    await startCreation(tester);
    await _elapse(tester, _step);

    expect(find.byKey(_stop), findsOneWidget);
    expect(find.byKey(_minimize), findsOneWidget);
    expect(find.byKey(_close), findsNothing);
    expect(find.byKey(_openProject), findsNothing);
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.byKey(_stop));
    await tester.pump();

    expect(memory.stopCalls, 1);
    await _elapse(tester, const Duration(seconds: 5));
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('completed offers open project and close', (tester) async {
    await pumpWindow(tester);
    await startCreation(tester);
    await _elapse(tester, const Duration(seconds: 3));

    expect(inProgress(find.text('avera_booking: done')), findsOneWidget);
    expect(find.byKey(_openProject), findsOneWidget);
    expect(find.byKey(_close), findsOneWidget);
    expect(find.text('Open project'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.byKey(_stop), findsNothing);
    expect(find.byKey(_minimize), findsNothing);
    expect(find.byKey(const ValueKey<String>('creation-open-chat')), findsNothing);
    expect(find.byKey(const ValueKey<String>('creation-done')), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('failed after create offers open project', (tester) async {
    await pumpWindow(tester);
    memory.failAt = CreationStepKind.analyze;
    await startCreation(tester);
    await _elapse(tester, const Duration(seconds: 3));

    expect(find.text('Could not create avera_booking'), findsOneWidget);
    expect(find.byKey(_openProject), findsOneWidget);
    expect(find.byKey(_close), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('failed without project offers only close', (tester) async {
    await pumpWindow(tester);
    memory
      ..failAt = CreationStepKind.flutterCreate
      ..completedProjectId = null;
    await startCreation(tester);
    await _elapse(tester, const Duration(seconds: 3));

    expect(find.text('Could not create avera_booking'), findsOneWidget);
    expect(find.byKey(_openProject), findsNothing);
    expect(find.byKey(_close), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('no preview note in any state', (tester) async {
    void expectNoNotes() {
      expect(find.text('Preview'), findsNothing);
      expect(find.textContaining('This is a preview'), findsNothing);
      expect(find.textContaining('The agent step is the usual'), findsNothing);
      expect(find.textContaining('M4'), findsNothing);
      expect(inProgress(find.textContaining('Claude Code')), findsNothing);
    }

    await pumpWindow(tester);
    await startCreation(tester);
    await _elapse(tester, _step);
    expectNoNotes();

    await _elapse(tester, const Duration(seconds: 3));
    expect(find.byKey(_close), findsOneWidget);
    expectNoNotes();
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();

    memory.failAt = CreationStepKind.analyze;
    await startCreation(tester, name: 'second_app');
    await _elapse(tester, const Duration(seconds: 3));
    expect(find.text('Could not create second_app'), findsOneWidget);
    expectNoNotes();
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('plain template shows two steps', (tester) async {
    await pumpWindow(tester);
    await openFromMenu(tester);
    await tester.enterText(find.byKey(_nameField), 'avera_booking');
    await tester.tap(find.text('Plain flutter create'));
    await tester.tap(find.byKey(const ValueKey<String>('new-project-git')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('new-project-create')));
    await tester.pump();

    expect(inProgress(find.text('○')), findsNWidgets(2));
    expect(find.text('git init'), findsNothing);
    expect(find.text('First commit'), findsNothing);

    await tester.tap(minimize(false));
    await _elapse(tester, const Duration(milliseconds: 300));
    expect(find.text('Creating avera_booking · 0/2'), findsOneWidget);

    await _elapse(tester, const Duration(seconds: 1));
    expect(find.text('avera_booking: done'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('shows only the last six lines of a step', (tester) async {
    await pumpWindow(
      tester,
      repository: _ChattyRepository(<String>[for (var i = 1; i <= 9; i++) 'line $i']),
    );
    await startCreation(tester);
    await _elapse(tester, _step);

    expect(find.text('line 3'), findsNothing);
    expect(find.text('line 4'), findsOneWidget);
    expect(find.text('line 9'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a failed step shows the failure and the chip says error', (tester) async {
    await pumpWindow(tester, repository: _FailingRepository());
    await startCreation(tester);
    await _elapse(tester, _step);

    expect(find.text('Could not create avera_booking'), findsOneWidget);
    expect(inProgress(find.text('✕')), findsOneWidget);
    expect(find.byKey(_close), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('avera_booking: error'), findsOneWidget);
    await tester.tap(chip());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    expect(chip(), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  for (final size in const <Size>[Size(900, 600), Size(1280, 800)]) {
    for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('fits ${size.width.toInt()}×${size.height.toInt()} in ${locale.languageCode}, '
            '${dark ? 'dark' : 'light'}', (tester) async {
          final ru = locale.languageCode == 'ru';
          await pumpWindow(tester, locale: locale, dark: dark, size: size, withLongProject: true);
          await startCreation(
            tester,
            name: 'avera_booking_with_a_very_long_package_name_indeed',
            ru: ru,
          );

          // In the middle: the agent step prints.
          await _elapse(tester, const Duration(milliseconds: 1000));
          expect(find.byType(CreationProgress), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Minimized: the chip sits in the sidebar next to a long project name.
          await tester.tap(minimize(ru));
          await _elapse(tester, const Duration(milliseconds: 300));
          expect(find.byType(CreationChip), findsOneWidget);
          expect(chip(), findsOneWidget);
          expect(tester.takeException(), isNull);

          // At the end.
          await _elapse(tester, const Duration(seconds: 2));
          await tester.tap(chip());
          await tester.pumpAndSettle();
          expect(find.text(ru ? 'Закрыть' : 'Close'), findsOneWidget);
          expect(find.text(ru ? 'Открыть проект' : 'Open project'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await disposeTestApp(tester, dependencies);
        });
      }
    }
  }
}

/// A run whose first step fails and then ends normally.
final class _FailingRepository implements IProjectCreationRepository {
  @override
  Future<String> defaultParent() async => '/Users/test/StudioProjects';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<CreationRun> create(NewProjectRequest request) async* {
    final kinds = creationStepsFor(request);
    yield CreationRun(steps: <CreationStep>[for (final kind in kinds) CreationStep(kind: kind)]);
    yield CreationRun(
      steps: <CreationStep>[
        CreationStep(kind: kinds.first, status: CreationStepStatus.failed),
        for (final kind in kinds.skip(1)) CreationStep(kind: kind),
      ],
    );
  }
}
