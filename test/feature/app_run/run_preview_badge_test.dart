import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_run_controls.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// A run repository that is not a stand-in: it runs nothing and says so.
final class _RealRun implements IAppRunRepository {
  @override
  bool get isPreview => false;

  @override
  Stream<RunState> watchRun(int projectId) => Stream<RunState>.value(const RunIdle());

  @override
  Stream<LogEntry> logs(int projectId) => const Stream<LogEntry>.empty();

  @override
  Future<void> markSent(int projectId, int seq) async {}

  @override
  Future<void> start(
    int projectId, {
    required String deviceId,
    required BuildMode mode,
    required String target,
  }) async {}

  @override
  Future<void> stop(int projectId) async {}

  @override
  Future<Duration> hotReload(int projectId) async => Duration.zero;

  @override
  Future<void> hotRestart(int projectId) async {}

  @override
  Future<void> dispose() async {}
}

final class _RealDevices implements IDevicesRepository {
  @override
  bool get isPreview => false;

  @override
  Stream<List<Device>> watchDevices() => Stream<List<Device>>.value(const <Device>[]);
}

final class _RealPicker implements IWidgetPickerRepository {
  @override
  bool get isPreview => false;

  @override
  Future<PickedWidget?> pick(int projectId) async => null;
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

    testWidgets('are not marked when run, devices and picker are real', (tester) async {
      final dependencies = testDependencies(
        appRunRepository: _RealRun(),
        devicesRepository: _RealDevices(),
        widgetPickerRepository: _RealPicker(),
      );
      final state = await pump(tester, dependencies);

      expect(state.runIsPreview, isFalse);
      expect(find.byType(WorkspaceRunControls), findsOneWidget);
      expect(badgeInTitleBar(), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    for (final (name, run, devices, picker) in <(String, bool, bool, bool)>[
      ('only the run is made up', true, false, false),
      ('only the devices are made up', false, true, false),
      ('only the picker is made up', false, false, true),
    ]) {
      testWidgets('are marked when $name', (tester) async {
        final dependencies = testDependencies(
          appRunRepository: run ? FakeAppRunRepositoryImpl() : _RealRun(),
          devicesRepository: devices ? FakeDevicesRepositoryImpl() : _RealDevices(),
          widgetPickerRepository: picker ? FakeWidgetPickerRepositoryImpl() : _RealPicker(),
        );
        final state = await pump(tester, dependencies);

        expect(state.runIsPreview, isTrue);
        expect(badgeInTitleBar(), findsOneWidget);
        await disposeTestApp(tester, dependencies);
      });
    }
  });
}
