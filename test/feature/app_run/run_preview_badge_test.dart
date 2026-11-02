import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/picked_widget_card.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_right_pane.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_run_controls.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_devices_repository.dart';
import '../../support/scripted_app_run_repository.dart';
import '../../support/scripted_widget_picker_repository.dart';
import '../../support/test_app.dart';

/// A picker that counts the picks it is asked for.
final class _CountingPicker implements IWidgetPickerRepository {
  int picks = 0;

  @override
  Future<PickResult> pick(int projectId) async {
    picks++;
    return const PickCancelled();
  }

  @override
  Future<void> cancel(int projectId) async {}

  @override
  Future<PickResult> select(int projectId, String id) async => const PickGone();

  @override
  Future<void> dispose() async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// A window with one selected project; returns the badge count in the title bar's run controls.
  Future<WorkspaceConfigWidgetState> pump(WidgetTester tester, Dependencies dependencies) async {
    useDesktopView(tester);
    final database = dependencies.database;
    final project = (await tester.runAsync(
      () => database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/p', name: 'p')),
    ))!;
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    final state = WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));
    state.dataController.selectProject(project);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    return state;
  }

  Finder badgeInTitleBar() =>
      find.descendant(of: find.byType(WorkspaceRunControls), matching: find.byType(PreviewBadge));

  group('the title bar run controls', () {
    testWidgets('are marked Preview while the run is made up', (tester) async {
      final dependencies = testDependencies();
      final state = await pump(tester, dependencies);

      expect(state.runIsPreview, isTrue);
      expect(find.byType(WorkspaceRunControls), findsOneWidget);
      expect(badgeInTitleBar(), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('are not marked when the run and the devices are real', (tester) async {
      final dependencies = testDependencies(
        appRunRepository: ScriptedAppRunRepository(),
        devicesRepository: MemoryDevicesRepository(),
        widgetPickerRepository: _CountingPicker(),
      );
      final state = await pump(tester, dependencies);

      expect(state.runIsPreview, isFalse);
      expect(find.byType(WorkspaceRunControls), findsOneWidget);
      expect(badgeInTitleBar(), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    for (final (name, run, devices) in <(String, bool, bool)>[
      ('only the run is made up', true, false),
      ('only the devices are made up', false, true),
    ]) {
      testWidgets('are marked when $name', (tester) async {
        final dependencies = testDependencies(
          appRunRepository: ScriptedAppRunRepository(isPreview: run),
          devicesRepository: MemoryDevicesRepository(isPreview: devices),
          widgetPickerRepository: _CountingPicker(),
        );
        final state = await pump(tester, dependencies);

        expect(state.runIsPreview, isTrue);
        expect(badgeInTitleBar(), findsOneWidget);
        await disposeTestApp(tester, dependencies);
      });
    }
  });

  group('the Run tab with a real run', () {
    Finder inPane(String tooltip) =>
        find.descendant(of: find.byType(WorkspaceRightPane), matching: find.byTooltip(tooltip));

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// Runs the app of the selected project: picking needs a running app.
    Future<void> runApp(WidgetTester tester, WorkspaceConfigWidgetState state, int project) async {
      state.dataController
        ..selectProject(project)
        ..selectPaneTab(RightPaneTab.run);
      for (var i = 0; i < 3; i++) {
        await settle(tester);
      }
      await tester.tap(inPane('Run'));
      for (var i = 0; i < 3 && state.runController.state.run is! RunRunning; i++) {
        await settle(tester);
      }
      expect(state.runController.state.run, isA<RunRunning>());
    }

    testWidgets('have no Preview badge in the header and pick through the picker', (tester) async {
      final picker = _CountingPicker();
      final dependencies = testDependencies(
        appRunRepository: ScriptedAppRunRepository(step: const Duration(milliseconds: 1)),
        devicesRepository: MemoryDevicesRepository(step: const Duration(milliseconds: 1)),
        widgetPickerRepository: picker,
      );
      final state = await pump(tester, dependencies);
      await runApp(tester, state, state.dataController.projectId!);

      expect(
        find.descendant(of: find.byType(WorkspaceRightPane), matching: find.byType(PreviewBadge)),
        findsNothing,
      );
      await tester.tap(inPane('Pick a widget in the app'));
      await tester.pump();

      expect(find.text('Coming in M6'), findsNothing);
      expect(picker.picks, 1);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('keep picking when the run is made up too', (tester) async {
      final picker = _CountingPicker();
      final dependencies = testDependencies(widgetPickerRepository: picker);
      final state = await pump(tester, dependencies);
      await runApp(tester, state, state.dataController.projectId!);

      await tester.tap(inPane('Pick a widget in the app'));
      await tester.pump();

      expect(find.text('Coming in M6'), findsNothing);
      expect(picker.picks, 1);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('no preview badge on the picker', (tester) async {
      final dependencies = testDependencies(
        widgetPickerRepository: ScriptedWidgetPickerRepository(step: const Duration(seconds: 1)),
      );
      final state = await pump(tester, dependencies);
      await runApp(tester, state, state.dataController.projectId!);
      Finder badgeOnCard() =>
          find.descendant(of: find.byType(PickedWidgetCard), matching: find.byType(PreviewBadge));

      await tester.tap(inPane('Pick a widget in the app'));
      await tester.pump();
      expect(find.byType(PickedWidgetCard), findsOneWidget);
      expect(badgeOnCard(), findsNothing, reason: 'while it waits for a tap');

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Add to message'), findsOneWidget);
      expect(
        badgeOnCard(),
        findsNothing,
        reason: 'with the picked widget, though the run is made up',
      );
      await disposeTestApp(tester, dependencies);
    });
  });
}
