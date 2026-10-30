import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_right_pane.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// A picker whose pick ends when the test says so.
final class _ManualPicker implements IWidgetPickerRepository {
  final List<Completer<PickedWidget?>> pending = <Completer<PickedWidget?>>[];

  @override
  bool get isPreview => true;

  @override
  Future<PickedWidget?> pick(int projectId) {
    final completer = Completer<PickedWidget?>();
    pending.add(completer);
    return completer.future;
  }
}

const PickedWidget _fromA = PickedWidget(
  name: 'WidgetOfA',
  file: 'lib/a.dart',
  line: 1,
  ancestors: <String>[],
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late _ManualPicker picker;
  late Dependencies dependencies;
  late int a;
  late int b;

  setUp(() {
    picker = _ManualPicker();
    dependencies = testDependencies(widgetPickerRepository: picker);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Finder inPane(String tooltip) =>
      find.descendant(of: find.byType(WorkspaceRightPane), matching: find.byTooltip(tooltip));

  Future<WorkspaceConfigWidgetState> pump(WidgetTester tester) async {
    useDesktopView(tester);
    await tester.runAsync(() async {
      final database = dependencies.database;
      a = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/a', name: 'proj-a'));
      b = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/b', name: 'proj-b'));
      for (final id in <int>[a, b]) {
        await database
            .into(database.sessionsTable)
            .insert(
              SessionsTableCompanion.insert(
                projectId: id,
                agentId: 'claude',
                title: Value<String>('Chat $id'),
              ),
            );
      }
    });
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    final state = WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));
    state.dataController
      ..selectProject(a)
      ..selectPaneTab(RightPaneTab.run);
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    // Picking needs a running app.
    await tester.tap(inPane('Run'));
    for (var i = 0; i < 3 && state.runController.state.run is! RunRunning; i++) {
      await settle(tester);
    }
    expect(state.runController.state.run, isA<RunRunning>());
    return state;
  }

  testWidgets('a widget picked in one project never lands in the next one', (tester) async {
    final state = await pump(tester);
    expect(state.runController.state.projectId, a);

    await tester.tap(inPane('Pick a widget in the app'));
    await tester.pump();
    expect(find.text('Tap a widget in the running app…'), findsOneWidget);

    state.dataController.selectProject(b);
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(state.runController.state.projectId, b);
    expect(
      find.text('Tap a widget in the running app…'),
      findsNothing,
      reason: 'project B never asked for a pick',
    );

    picker.pending.single.complete(_fromA);
    await settle(tester);
    await settle(tester);

    expect(state.runActionsController.state, isA<RunActions$CompletedState>());
    expect(state.runController.state.projectId, b);
    expect(state.runController.state.picked, isNull);
    expect(find.text('WidgetOfA'), findsNothing);
    expect(find.text('Add to message'), findsNothing);
    expect(state.runLink.mentions, isNull, reason: 'the @ menu offers nothing from project A');
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a pick finished in the selected project is kept', (tester) async {
    final state = await pump(tester);

    await tester.tap(inPane('Pick a widget in the app'));
    await tester.pump();
    picker.pending.single.complete(_fromA);
    await settle(tester);
    await settle(tester);

    expect(state.runController.state.picked, _fromA);
    expect(find.text('WidgetOfA'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });
}
