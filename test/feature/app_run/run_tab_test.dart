import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_tab.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// A repository that replays what a test preloads and emits what it pushes.
final class _ScriptedRunRepository implements IAppRunRepository {
  final StreamController<LogEntry> _live = StreamController<LogEntry>.broadcast();
  final List<LogEntry> buffer = <LogEntry>[];
  RunState state = const RunIdle();

  @override
  bool get isPreview => false;

  void push(LogEntry entry) {
    buffer.add(entry);
    _live.add(entry);
  }

  @override
  Stream<LogEntry> logs(int projectId) async* {
    for (final entry in List<LogEntry>.of(buffer)) {
      yield entry;
    }
    yield* _live.stream;
  }

  @override
  Stream<RunState> watchRun(int projectId) => Stream<RunState>.value(state);

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
  Future<void> dispose() => _live.close();
}

const Device _macos = Device(
  id: 'macos',
  name: 'macOS',
  platform: DevicePlatform.macos,
  kind: DeviceKind.running,
);

LogEntry _line(int seq, {LogLevel level = LogLevel.info}) =>
    LogEntry(seq: seq, time: DateTime(2026, 10, 30), level: level, text: 'line $seq');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('RunTab', () {
    late Dependencies dependencies;
    late DevicesController devices;
    late RunController run;
    late RunActionsController actions;
    late List<RunError> sentErrors;
    late List<(String, int?)> openedFiles;

    setUp(() {
      dependencies = testDependencies();
      devices = DevicesController(repository: dependencies.devicesRepository);
      run = RunController(repository: dependencies.appRunRepository);
      actions = RunActionsController(
        runRepository: dependencies.appRunRepository,
        pickerRepository: dependencies.widgetPickerRepository,
      );
      sentErrors = <RunError>[];
      openedFiles = <(String, int?)>[];
    });

    tearDown(() {
      devices.dispose();
      run.dispose();
      actions.dispose();
    });

    Future<void> pumpTab(
      WidgetTester tester, {
      int? projectId = 1,
      Dependencies? override,
      Size size = const Size(1280, 800),
      bool loadDevices = true,
      double width = 400,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (projectId != null) run.watch(projectId);
      if (loadDevices) devices.watch();
      await tester.pumpWidget(
        testApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: RunTab(
                projectId: projectId,
                isPreview: true,
                devices: devices,
                run: run,
                actions: actions,
                onSendError: sentErrors.add,
                onAddWidget: (_) {},
                onOpenFile: (path, line) => openedFiles.add((path, line)),
              ),
            ),
          ),
          dependencies: override ?? dependencies,
          withSettings: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }

    /// Lets the fake scenario run for [duration] of fake time.
    Future<void> elapse(WidgetTester tester, [int milliseconds = 20]) =>
        tester.pump(Duration(milliseconds: milliseconds));

    Future<void> startAndReload(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Run'));
      await elapse(tester);
      await tester.tap(find.byTooltip('Hot reload'));
      await elapse(tester);
    }

    testWidgets('without a project it shows the empty state', (tester) async {
      await pumpTab(tester, projectId: null);

      expect(find.text('Select a project to run its app'), findsOneWidget);
      expect(find.byTooltip('Run'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('run builds then shows the running state', (tester) async {
      await pumpTab(tester);
      expect(find.text('Not running'), findsOneWidget);
      expect(find.byTooltip('Stop the app'), findsNothing);

      await tester.tap(find.byTooltip('Run'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Resolving dependencies'), findsOneWidget);
      expect(find.byTooltip('Stop the app'), findsOneWidget);

      await elapse(tester);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Running 0:'), findsOneWidget);
      expect(find.textContaining('Launching lib/main.dart'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('stopping the app returns to the idle status', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byTooltip('Run'));
      await elapse(tester);
      await tester.tap(find.byTooltip('Stop the app'));
      await elapse(tester);

      expect(find.text('Not running'), findsOneWidget);
      expect(find.byTooltip('Run'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('reload produces an error block with actions', (tester) async {
      await pumpTab(tester);
      await startAndReload(tester);

      expect(find.text('Layout overflow'), findsOneWidget);
      expect(find.text('A RenderFlex overflowed by 24 pixels on the right.'), findsOneWidget);
      expect(find.text('Errors 1'), findsOneWidget);

      await tester.tap(find.text('Send to the agent'));
      expect(sentErrors.single.title, 'Layout overflow');

      await tester.tap(find.text('Open file'));
      expect(openedFiles.single, ('lib/src/feature/booking/widgets/booking_card.dart', 42));

      expect(find.textContaining('RenderFlex.paint'), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pump();
      expect(find.textContaining('RenderFlex.paint'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the errors filter and search narrow the logs', (tester) async {
      await pumpTab(tester);
      await startAndReload(tester);
      expect(find.textContaining('Booking loaded'), findsOneWidget);
      expect(find.textContaining('Reloaded 3 of 812'), findsOneWidget);

      await tester.tap(find.text('Errors 1'));
      await tester.pump();
      expect(find.textContaining('Booking loaded'), findsNothing);
      expect(find.text('A RenderFlex overflowed by 24 pixels on the right.'), findsOneWidget);

      await tester.tap(find.text('To agent'));
      await tester.pump();
      expect(find.text('A RenderFlex overflowed by 24 pixels on the right.'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'BOOKING LOADED');
      await tester.pump();
      expect(find.textContaining('Booking loaded'), findsOneWidget);
      expect(find.textContaining('Reloaded 3 of 812'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('clearing the logs empties the list and the error count', (tester) async {
      await pumpTab(tester);
      await startAndReload(tester);

      await tester.tap(find.byTooltip('Clear the logs'));
      await tester.pump();

      expect(find.textContaining('Booking loaded'), findsNothing);
      expect(find.text('Layout overflow'), findsNothing);
      expect(find.text('Errors'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('devices menu shows running and available devices; arguments say M2', (
      tester,
    ) async {
      await pumpTab(tester);
      expect(find.text('iPhone 16 Pro'), findsOneWidget);

      await tester.tap(find.text('iPhone 16 Pro'));
      await tester.pumpAndSettle();

      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Available to launch'), findsOneWidget);
      expect(find.text('macOS'), findsOneWidget);
      expect(find.text('Pixel 9 API 35'), findsOneWidget);
      expect(find.textContaining('--flavor'), findsOneWidget);
      expect(find.text('Coming in M2'), findsOneWidget);

      await tester.tap(find.textContaining('--flavor'));
      await tester.pumpAndSettle();
      expect(
        find.text('Pixel 9 API 35'),
        findsOneWidget,
        reason: 'the disabled item keeps the menu',
      );

      await tester.tap(find.text('Pixel 9 API 35'));
      await tester.pumpAndSettle();
      expect(run.state.selectedDeviceId, 'android-pixel-9');
      expect(find.text('Pixel 9 API 35'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the mode chip chooses the build mode', (tester) async {
      await pumpTab(tester);

      await tester.tap(find.text('debug'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('release'));
      await tester.pumpAndSettle();

      expect(run.state.mode, BuildMode.release);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('screenshot and DevTools say they come in M2', (tester) async {
      await pumpTab(tester);

      await tester.tap(find.byTooltip('Screenshot'));
      await tester.pump();
      expect(find.text('Coming in M2'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byType(RunTab))).clearSnackBars();
      await tester.pump();
      await tester.tap(find.byTooltip('Open DevTools'));
      await tester.pump();
      expect(find.text('Coming in M2'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Run is disabled until a device is chosen', (tester) async {
      await pumpTab(tester, loadDevices: false);
      expect(find.text('Choose a device'), findsOneWidget);
      final run = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.play_arrow), matching: find.byType(IconButton)),
      );
      expect(run.onPressed, isNull);
      expect(find.byTooltip('Choose a device to run on'), findsOneWidget);

      devices.watch();
      await elapse(tester);
      expect(find.text('Choose a device'), findsNothing);
      expect(find.byTooltip('Run'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('reload and picking do nothing while the app is not running', (tester) async {
      await pumpTab(tester);

      await tester.tap(find.byTooltip('Hot reload'), warnIfMissed: false);
      await elapse(tester);

      expect(find.textContaining('Reloaded'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a 340 px pane with an error and a picked widget does not overflow', (
      tester,
    ) async {
      await pumpTab(tester, width: 340, size: const Size(900, 900));
      run.setPicked(
        const PickedWidget(
          name: 'BookingCard',
          file: 'lib/src/feature/booking/widgets/booking_card.dart',
          line: 42,
          ancestors: <String>['Row', 'Padding', 'BookingCard', 'ListView', 'BookingScreen'],
        ),
      );
      await startAndReload(tester);
      await tester.tap(find.text('Details'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the reload-after-turn switch is shown', (tester) async {
      await pumpTab(tester);

      expect(find.text('Hot reload after every agent turn'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    group('with a scripted run', () {
      late _ScriptedRunRepository scripted;

      Future<void> pumpScripted(
        WidgetTester tester, {
        int lines = 2000,
        Duration runningFor = Duration.zero,
      }) async {
        scripted = _ScriptedRunRepository()
          ..state = RunRunning(
            device: _macos,
            startedAt: DateTime.now().subtract(runningFor),
            lastReload: const Duration(milliseconds: 180),
          );
        for (var i = 0; i < lines; i++) {
          scripted.buffer.add(_line(i, level: i % 500 == 0 ? LogLevel.error : LogLevel.info));
        }
        run.dispose();
        run = RunController(repository: scripted);
        await pumpTab(tester, size: const Size(900, 600));
      }

      testWidgets('the status line shows the running time and the last reload', (tester) async {
        await pumpScripted(tester, lines: 3, runningFor: const Duration(minutes: 4, seconds: 12));

        expect(find.textContaining('Running 4:1'), findsOneWidget);
        expect(find.textContaining('reload 180 ms'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        expect(find.textContaining('Running 4:'), findsOneWidget);
        await disposeTestApp(tester, dependencies);
        await scripted.dispose();
      });

      testWidgets('2000 log lines scroll without jank and without overflow at 900×600', (
        tester,
      ) async {
        await pumpScripted(tester);

        expect(tester.takeException(), isNull);
        final built = find.textContaining('line ').evaluate().length;
        expect(built, greaterThan(0));
        expect(built, lessThan(100));
        expect(find.text('line 1999'), findsOneWidget, reason: 'starts at the bottom');

        await tester.drag(find.text('line 1999'), const Offset(0, 4000));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('line ').evaluate().length, lessThan(100));
        await disposeTestApp(tester, dependencies);
        await scripted.dispose();
      });

      testWidgets('new lines follow the end only while the user is at the bottom', (tester) async {
        await pumpScripted(tester, lines: 300);
        expect(find.text('line 299'), findsOneWidget);

        scripted.push(_line(300));
        await tester.pump();
        await tester.pump();
        expect(find.text('line 300'), findsOneWidget, reason: 'at the bottom: follows');

        await tester.drag(find.text('line 300'), const Offset(0, 600));
        await tester.pump();
        expect(find.text('line 300'), findsNothing);
        final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
        final before = scrollable.position.pixels;

        scripted.push(_line(301));
        await tester.pump();
        await tester.pump();

        expect(scrollable.position.pixels, before, reason: 'scrolled up: stays');
        expect(find.text('line 301'), findsNothing);
        await disposeTestApp(tester, dependencies);
        await scripted.dispose();
      });
    });
  });

  group('in the right pane', () {
    late Dependencies dependencies;

    setUp(() => dependencies = testDependencies());

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<WorkspaceConfigWidgetState> pump(WidgetTester tester, {Size? size}) async {
      tester.view
        ..physicalSize = size ?? const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        final database = dependencies.database;
        final project = await database
            .into(database.projectsTable)
            .insert(ProjectsTableCompanion.insert(path: '/p', name: 'p'));
        await database
            .into(database.sessionsTable)
            .insert(
              SessionsTableCompanion.insert(
                projectId: project,
                agentId: 'claude',
                title: const Value<String>('Chat'),
              ),
            );
      });
      await tester.pumpWidget(
        testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat'));
      for (var i = 0; i < 5; i++) {
        await settle(tester);
      }
      final state = WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));
      state.dataController.selectPaneTab(RightPaneTab.run);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      return state;
    }

    testWidgets('an error in the run puts a badge on the tab', (tester) async {
      await pump(tester);
      expect(find.text('Not running'), findsOneWidget);

      await tester.tap(find.byTooltip('Run'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byTooltip('Hot reload'));
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('Layout overflow'), findsOneWidget);
      expect(find.text('1'), findsOneWidget, reason: 'the badge of the Run tab');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('picking a widget shows its card', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Run'));
      await tester.pump(const Duration(milliseconds: 20));

      await tester.tap(find.byTooltip('Pick a widget in the app'));
      await tester.pump();
      expect(find.text('Tap a widget in the running app…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('Tap a widget in the running app…'), findsNothing);
      expect(find.text('BookingCard'), findsOneWidget);
      expect(find.text('booking_card.dart:42'), findsOneWidget);
      expect(find.text('Row › Padding › BookingCard › ListView › BookingScreen'), findsOneWidget);
      expect(find.text('Add to message'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the picked widget survives a later action', (tester) async {
      final state = await pump(tester);
      await tester.tap(find.byTooltip('Run'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byTooltip('Pick a widget in the app'));
      await tester.pump(const Duration(milliseconds: 20));

      await tester.tap(find.byTooltip('Hot reload'));
      await tester.pump(const Duration(milliseconds: 20));

      expect(state.runController.state.picked, isA<PickedWidget>());
      expect(find.text('BookingCard'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('900×600 with the run tab does not overflow', (tester) async {
      final state = await pump(tester, size: const Size(900, 600));
      state.toggleRightPane(windowWidth: 900);
      await settle(tester);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Run'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byTooltip('Hot reload'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byTooltip('Pick a widget in the app'));
      await tester.pump(const Duration(milliseconds: 20));

      expect(tester.takeException(), isNull);
      await disposeTestApp(tester, dependencies);
    });
  });
}
