import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_config_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_tab.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_right_pane.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_devices_repository.dart';
import '../../support/scripted_app_run_repository.dart';
import '../../support/scripted_widget_picker_repository.dart';
import '../../support/test_app.dart';

/// A repository that replays what a test preloads and emits what it pushes.
final class _ScriptedRunRepository implements IAppRunRepository {
  final StreamController<LogEntry> _live = StreamController<LogEntry>.broadcast();
  final List<LogEntry> buffer = <LogEntry>[];
  RunState state = const RunIdle();

  @override
  RunState currentRun(int projectId) => state;

  @override
  List<LogEntry> recentLogs(int projectId, {int limit = kRunLogLimit}) => List.of(buffer);

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
    required Device device,
    required BuildMode mode,
    required String target,
    RunArguments arguments = const RunArguments(),
    Map<String, String> environment = const <String, String>{},
  }) async {}

  @override
  Future<void> stop(int projectId) async {}

  @override
  Future<Duration> hotReload(int projectId) async => Duration.zero;

  @override
  Future<Duration> hotRestart(int projectId) async => Duration.zero;

  @override
  Future<void> openDevTools(int projectId) async {}

  @override
  Future<String?> screenshot(int projectId) async => null;

  @override
  Future<void> dispose() => _live.close();
}

/// A devices repository whose stream fails with [error] (when set) and counts how often it was
/// asked.
final class _FailingDevicesRepository implements IDevicesRepository {
  _FailingDevicesRepository(this.error);

  final Object error;
  int watches = 0;

  @override
  bool get isPreview => false;

  @override
  Stream<List<Device>> watchDevices() {
    watches++;
    final controller = StreamController<List<Device>>();
    controller.onListen = () {
      controller
        ..addError(error)
        ..close().ignore();
    };
    return controller.stream;
  }

  @override
  Future<void> launch(String deviceId) async {}

  @override
  Future<void> dispose() async {}
}

const Device _pixelEmulator = Device(
  id: 'emulator:Pixel_9',
  name: 'Pixel 9',
  platform: DevicePlatform.android,
  kind: DeviceKind.available,
  emulatorId: 'Pixel_9',
);

const Device _pixelRunning = Device(
  id: 'emulator-5554',
  name: 'sdk gphone64',
  platform: DevicePlatform.android,
  kind: DeviceKind.running,
  emulatorId: 'Pixel_9',
);

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
    late ScriptedWidgetPickerRepository picker;
    late DevicesController devices;
    late RunController run;
    late RunActionsController actions;
    late RunConfigController runConfig;
    late List<LogEntry> sentErrors;
    late List<(String, int?)> openedFiles;

    setUp(() {
      // A pick waits until the test ends it (or a cancel does), like a real one waits for a tap.
      picker = ScriptedWidgetPickerRepository(step: const Duration(hours: 1));
      dependencies = testDependencies(widgetPickerRepository: picker);
      devices = DevicesController(repository: dependencies.devicesRepository);
      run = RunController(
        repository: dependencies.appRunRepository,
        configRepository: dependencies.runConfigRepository,
      );
      actions = RunActionsController(
        runRepository: dependencies.appRunRepository,
        pickerRepository: dependencies.widgetPickerRepository,
      );
      runConfig = RunConfigController(repository: dependencies.runConfigRepository);
      sentErrors = <LogEntry>[];
      openedFiles = <(String, int?)>[];
    });

    tearDown(() {
      devices.dispose();
      run.dispose();
      actions.dispose();
      runConfig.dispose();
    });

    Future<void> pumpTab(
      WidgetTester tester, {
      int? projectId = 1,
      Dependencies? override,
      Size size = const Size(1280, 800),
      bool loadDevices = true,
      bool chooseDevice = true,
      double width = 400,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (projectId != null) run.watch(projectId);
      if (loadDevices) devices.watch();
      if (chooseDevice) run.choose(deviceId: 'ios-sim-16-pro');
      await tester.pumpWidget(
        testApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: RunTab(
                projectId: projectId,
                projectRoot: '/p',
                isPreview: true,
                devices: devices,
                run: run,
                actions: actions,
                runConfig: runConfig,
                onSendError: sentErrors.add,
                onAddWidget: (_) {},
                onOpenFile: (path, line) => openedFiles.add((path, line)),
                onOpenFlutterSettings: () {},
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
      expect(sentErrors.single.error!.title, 'Layout overflow');

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

    testWidgets('devices menu shows running and available devices and the run arguments', (
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
      expect(find.text('Run arguments…'), findsOneWidget);
      expect(find.text('None'), findsOneWidget, reason: 'no arguments yet');
      expect(find.textContaining('Coming in'), findsNothing);

      await tester.tap(find.text('Pixel 9 API 35'));
      await tester.pumpAndSettle();
      expect(run.state.selectedDeviceId, 'android-pixel-9');
      expect(find.text('Pixel 9 API 35'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('Run arguments… opens the dialog; a saved flavor is summed up and started with', (
      tester,
    ) async {
      final scripted = dependencies.appRunRepository as ScriptedAppRunRepository;
      await pumpTab(tester);

      await tester.tap(find.text('iPhone 16 Pro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run arguments…'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey<String>('run-arguments-flavor')), 'dev');
      await tester.enterText(
        find.byKey(const ValueKey<String>('run-arguments-defines')),
        'A=1\nB=2',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        run.state.arguments,
        const RunArguments(flavor: 'dev', dartDefines: <String>['A=1', 'B=2']),
      );

      await tester.tap(find.text('iPhone 16 Pro'));
      await tester.pumpAndSettle();
      expect(find.text('--flavor dev · 2 defines'), findsOneWidget);
      await tester.tapAt(const Offset(1200, 700));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Run'));
      await elapse(tester);

      expect(scripted.starts, hasLength(1));
      expect(scripted.starts.single.arguments.toFlutterArgs(), <String>[
        '--flavor',
        'dev',
        '--dart-define',
        'A=1',
        '--dart-define',
        'B=2',
      ]);
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

    group('screenshot and DevTools', () {
      ScriptedAppRunRepository scripted() =>
          dependencies.appRunRepository as ScriptedAppRunRepository;

      bool enabled(WidgetTester tester, IconData icon) =>
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon)).onPressed != null;

      testWidgets('are off until the app runs, and the tooltips say what to wait for', (
        tester,
      ) async {
        await pumpTab(tester);

        expect(enabled(tester, Icons.photo_camera_outlined), isFalse);
        expect(enabled(tester, Icons.open_in_new), isFalse);
        expect(find.byTooltip('Screenshots are available in a debug run'), findsOneWidget);
        expect(find.byTooltip('Open DevTools'), findsOneWidget);
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('a debug run turns both on; they act on the project', (tester) async {
        await pumpTab(tester);
        await tester.tap(find.byTooltip('Run'));
        await elapse(tester);

        expect(enabled(tester, Icons.photo_camera_outlined), isTrue);
        expect(enabled(tester, Icons.open_in_new), isTrue);
        expect(find.byTooltip('Screenshot'), findsOneWidget);

        await tester.tap(find.byTooltip('Screenshot'));
        await elapse(tester);
        await tester.tap(find.byTooltip('Open DevTools'));
        await elapse(tester);

        expect(scripted().screenshotCalls, <int>[1]);
        expect(scripted().devToolsOpened, <int>[1]);
        expect(find.textContaining('Coming in'), findsNothing);
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('a profile run has DevTools but no screenshot and no hot reload', (tester) async {
        await pumpTab(tester);
        run.choose(mode: BuildMode.profile);
        await tester.tap(find.byTooltip('Run'));
        await elapse(tester);

        expect(enabled(tester, Icons.photo_camera_outlined), isFalse);
        expect(find.byTooltip('Screenshots are available in a debug run'), findsOneWidget);
        expect(enabled(tester, Icons.open_in_new), isTrue);
        expect(enabled(tester, Icons.bolt), isFalse);
        expect(enabled(tester, Icons.refresh), isFalse);
        expect(find.byTooltip('Hot reload works in a debug run'), findsOneWidget);
        expect(find.byTooltip('Hot restart works in a debug run'), findsOneWidget);
        await disposeTestApp(tester, dependencies);
      });
    });

    testWidgets('Run is disabled until a device is chosen', (tester) async {
      await pumpTab(tester, chooseDevice: false);
      expect(find.text('Choose a device'), findsOneWidget, reason: 'the tab never picks for you');
      final startButton = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.play_arrow), matching: find.byType(IconButton)),
      );
      expect(startButton.onPressed, isNull);
      expect(find.byTooltip('Choose a device to run on'), findsOneWidget);

      run.choose(deviceId: 'macos');
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

    group('the widget picker', () {
      ScriptedAppRunRepository scripted() =>
          dependencies.appRunRepository as ScriptedAppRunRepository;

      Finder pickButton() => find.widgetWithIcon(IconButton, Icons.ads_click);

      bool canPick(WidgetTester tester) =>
          tester.widget<IconButton>(pickButton()).onPressed != null;

      const hint = 'Tap a widget in the running app…';

      Text link(WidgetTester tester, int index) => tester.widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey<String>('picked-link-$index')),
          matching: find.byType(Text),
        ),
      );

      Future<void> startAndPick(WidgetTester tester) async {
        await tester.tap(find.byTooltip('Run'));
        await elapse(tester);
        expect(run.state.run, isA<RunRunning>());
        await tester.tap(find.byTooltip('Pick a widget in the app'));
        await elapse(tester);
        expect(find.text(hint), findsOneWidget);
        expect(picker.isPicking(1), isTrue);
      }

      testWidgets('pick button disabled with each reason', (tester) async {
        await pumpTab(tester);
        expect(canPick(tester), isFalse);
        expect(find.byTooltip('The app is not running'), findsOneWidget);

        final startedAt = DateTime.now();
        scripted().setRunState(
          1,
          RunRunning(
            device: _macos,
            startedAt: startedAt,
            mode: BuildMode.profile,
            vmServiceUri: ScriptedAppRunRepository.vmServiceUri,
          ),
        );
        await elapse(tester);
        expect(canPick(tester), isFalse);
        expect(find.byTooltip('Picking works in debug builds only'), findsOneWidget);

        scripted().setRunState(1, RunRunning(device: _macos, startedAt: startedAt));
        await elapse(tester);
        expect(canPick(tester), isFalse);
        expect(find.byTooltip("Waiting for the app's VM service"), findsOneWidget);

        scripted().setRunState(
          1,
          RunRunning(
            device: _macos,
            startedAt: startedAt,
            vmServiceUri: ScriptedAppRunRepository.vmServiceUri,
          ),
        );
        await elapse(tester);
        expect(canPick(tester), isTrue);
        expect(find.byTooltip('Pick a widget in the app'), findsOneWidget);
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('stop while picking stops the run and cancels the pick', (tester) async {
        await pumpTab(tester);
        await startAndPick(tester);

        await tester.tap(find.byTooltip('Stop the app'));
        await elapse(tester);

        expect(run.state.run, isA<RunStopped>());
        expect(picker.cancels, <int>[1]);
        expect(picker.isPicking(1), isFalse);
        expect(find.text(hint), findsNothing);
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('hot reload while picking runs', (tester) async {
        await pumpTab(tester);
        await startAndPick(tester);

        await tester.tap(find.byTooltip('Hot reload'));
        await elapse(tester);

        expect(find.textContaining('Reloaded'), findsOneWidget, reason: 'not dropped');
        expect(picker.cancels, <int>[1]);
        expect(find.text(hint), findsNothing);
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('hot restart while picking runs', (tester) async {
        await pumpTab(tester);
        await startAndPick(tester);

        await tester.tap(find.byTooltip('Hot restart'));
        await elapse(tester);

        expect(find.textContaining('Restarted application'), findsOneWidget, reason: 'not dropped');
        expect(picker.cancels, <int>[1]);
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('a screenshot while picking is taken and the pick keeps waiting', (tester) async {
        await pumpTab(tester);
        await startAndPick(tester);

        await tester.tap(find.byTooltip('Screenshot'));
        await elapse(tester);

        expect(scripted().screenshotCalls, <int>[1]);
        expect(find.text(hint), findsOneWidget);
        expect(picker.cancels, isEmpty);
        await tester.tap(find.text('Cancel'));
        await elapse(tester);
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('cancel ends the pick; the next pick shows the hint', (tester) async {
        await pumpTab(tester);
        await startAndPick(tester);

        await tester.tap(find.text('Cancel'));
        await elapse(tester);

        expect(picker.cancels, <int>[1]);
        expect(find.text(hint), findsNothing);
        expect(find.text('Cancel'), findsNothing);

        await tester.tap(find.byTooltip('Pick a widget in the app'));
        await elapse(tester);
        expect(picker.picks, <int>[1, 1], reason: 'the next pick is not dropped');
        expect(find.text(hint), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await elapse(tester);
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('a picked widget fills the card', (tester) async {
        await pumpTab(tester);
        await startAndPick(tester);

        picker.complete(1);
        await elapse(tester);

        expect(find.text(hint), findsNothing);
        expect(find.text('booking_card.dart:42:7'), findsOneWidget);
        expect(link(tester, 0).data, 'BookingCard');
        expect(link(tester, 1).data, 'BookingList');
        expect(link(tester, 2).data, 'BookingScreen');
        expect(find.text('Add to message'), findsOneWidget);
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('tapping an ancestor selects it and moves the highlight', (tester) async {
        await pumpTab(tester);
        await startAndPick(tester);
        picker.complete(1);
        await elapse(tester);
        final colors = tester.element(find.byType(RunTab)).colors;
        expect(link(tester, 0).style?.color, colors.accent);

        picker.selectResult = const PickPicked(
          PickedWidget(
            name: 'BookingList',
            file: 'lib/src/feature/booking/widgets/booking_list.dart',
            line: 20,
            column: 5,
            id: 'inspector-list',
            ancestors: <PickedAncestor>[
              PickedAncestor(
                name: 'BookingScreen',
                file: 'lib/src/feature/booking/widgets/booking_screen.dart',
                line: 9,
                column: 12,
                id: 'inspector-screen',
              ),
            ],
          ),
        );
        await tester.tap(find.byKey(const ValueKey<String>('picked-link-1')));
        await elapse(tester);

        expect(picker.selects, <(int, String)>[(1, 'inspector-list')]);
        expect(find.text('booking_list.dart:20:5'), findsOneWidget);
        expect(link(tester, 0).data, 'BookingCard', reason: 'the picked one stays in the chain');
        expect(link(tester, 1).data, 'BookingList');
        expect(link(tester, 2).data, 'BookingScreen');
        expect(link(tester, 1).style?.color, colors.accent);
        expect(link(tester, 0).style?.color, isNot(colors.accent));

        picker.selectResult = const PickPicked(ScriptedWidgetPickerRepository.bookingCard);
        await tester.tap(find.byKey(const ValueKey<String>('picked-link-0')));
        await elapse(tester);
        expect(picker.selects.last, (1, 'inspector-card'));
        expect(link(tester, 0).style?.color, colors.accent);
        expect(find.text('booking_card.dart:42:7'), findsOneWidget);
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('a link that is gone says so and keeps the card', (tester) async {
        await pumpTab(tester);
        await startAndPick(tester);
        picker.complete(1);
        await elapse(tester);

        picker.selectResult = const PickGone();
        await tester.tap(find.byKey(const ValueKey<String>('picked-link-2')));
        await elapse(tester);

        expect(find.text('This widget is gone, pick again'), findsOneWidget);
        expect(find.text('booking_card.dart:42:7'), findsOneWidget);
        expect(link(tester, 0).data, 'BookingCard');
        await disposeTestApp(tester, dependencies);
      });

      testWidgets('a tap outside the project widgets says so', (tester) async {
        await pumpTab(tester);
        await startAndPick(tester);

        picker
          ..result = const PickNoProjectWidget()
          ..complete(1);
        await elapse(tester);

        expect(find.text('No widget of your project here'), findsOneWidget);
        await disposeTestApp(tester, dependencies);
      });
    });

    testWidgets('a 340 px pane with an error and a picked widget does not overflow', (
      tester,
    ) async {
      await pumpTab(tester, width: 340, size: const Size(900, 900));
      await startAndReload(tester);
      actions.pickWidget(1);
      picker.complete(1);
      await elapse(tester);
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
        run = RunController(
          repository: scripted,
          configRepository: dependencies.runConfigRepository,
        );
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

      testWidgets('DevTools waits for its address and says so', (tester) async {
        await pumpScripted(tester, lines: 1);

        expect(find.byTooltip('DevTools is starting…'), findsOneWidget);
        expect(
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.open_in_new)).onPressed,
          isNull,
        );
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

      testWidgets('past the log limit a scrolled-up list stays put and a chip jumps to the end', (
        tester,
      ) async {
        await pumpScripted(tester);
        Set<String> built() => <String>{
          for (final element in find.textContaining('line ').evaluate())
            (element.widget as Text).data!,
        };

        await tester.drag(find.text('line 1999'), const Offset(0, 1500));
        await tester.pump();
        final before = built();
        expect(find.textContaining('new line'), findsNothing);

        for (var i = 2000; i < 2003; i++) {
          scripted.push(_line(i));
        }
        await tester.pump();
        await tester.pump();

        expect(run.state.logs.first.seq, 3, reason: 'the limit dropped the oldest lines');
        expect(built(), before, reason: 'what the user reads did not slide');
        expect(find.text('3 new lines ↓'), findsOneWidget);

        await tester.tap(find.text('3 new lines ↓'));
        await tester.pump();
        await tester.pump();

        expect(find.text('line 2002'), findsOneWidget);
        expect(find.textContaining('new line'), findsNothing);

        scripted.push(_line(2003));
        await tester.pump();
        await tester.pump();
        expect(find.text('line 2003'), findsOneWidget, reason: 'following again');
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

  group('RunTab with real devices', () {
    late Dependencies dependencies;
    late DevicesController devices;
    late RunController run;
    late RunActionsController actions;
    late RunConfigController runConfig;
    late MemoryDevicesRepository fake;
    late int settingsOpened;

    Future<void> pumpTab(
      WidgetTester tester, {
      IDevicesRepository? repository,
      Size size = const Size(1280, 800),
      double width = 400,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      fake = MemoryDevicesRepository(step: const Duration(milliseconds: 1));
      dependencies = testDependencies(devicesRepository: repository ?? fake);
      devices = DevicesController(repository: dependencies.devicesRepository);
      run = RunController(
        repository: dependencies.appRunRepository,
        configRepository: dependencies.runConfigRepository,
      );
      actions = RunActionsController(
        runRepository: dependencies.appRunRepository,
        pickerRepository: dependencies.widgetPickerRepository,
      );
      runConfig = RunConfigController(repository: dependencies.runConfigRepository);
      settingsOpened = 0;
      run.watch(1);
      devices.watch();
      await tester.pumpWidget(
        testApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: RunTab(
                projectId: 1,
                projectRoot: '/p',
                isPreview: false,
                devices: devices,
                run: run,
                actions: actions,
                runConfig: runConfig,
                onSendError: (_) {},
                onAddWidget: (_) {},
                onOpenFile: (path, line) {},
                onOpenFlutterSettings: () => settingsOpened++,
              ),
            ),
          ),
          dependencies: dependencies,
          withSettings: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }

    Future<void> finish(WidgetTester tester) async {
      devices.dispose();
      run.dispose();
      actions.dispose();
      runConfig.dispose();
      await disposeTestApp(tester, dependencies);
    }

    IconButton startButton(WidgetTester tester) => tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.play_arrow), matching: find.byType(IconButton)),
    );

    testWidgets('no Flutter SDK says so and links to the Flutter settings', (tester) async {
      await pumpTab(
        tester,
        repository: _FailingDevicesRepository(const FlutterNotFoundException()),
      );

      expect(find.text('Flutter SDK not found'), findsOneWidget);
      expect(find.text('Choose a device'), findsNothing, reason: 'no device list to choose from');

      await tester.tap(find.text('Settings → Flutter'));
      expect(settingsOpened, 1);
      await finish(tester);
    });

    testWidgets('another error offers a retry that follows the devices again', (tester) async {
      final failing = _FailingDevicesRepository(StateError('daemon died'));
      await pumpTab(tester, repository: failing);

      expect(find.text('Could not get the devices'), findsOneWidget);
      expect(find.text('Flutter SDK not found'), findsNothing);
      expect(failing.watches, 1);

      await tester.tap(find.text('Retry'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 20));

      expect(failing.watches, 2);
      await finish(tester);
    });

    testWidgets('an empty list tells to start a simulator or an emulator', (tester) async {
      await pumpTab(tester);
      fake.set(const <Device>[]);
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('No devices: start a simulator or an emulator'), findsOneWidget);
      expect(find.text('Settings → Flutter'), findsNothing);
      await finish(tester);
    });

    testWidgets('choosing an available device launches it and keeps Run disabled', (tester) async {
      await pumpTab(tester);
      fake.set(const <Device>[_macos, _pixelEmulator]);
      await tester.pump(const Duration(milliseconds: 20));
      run.choose(deviceId: 'macos');
      await tester.pump();
      expect(startButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('macOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pixel 9'));
      await tester.pumpAndSettle();

      expect(fake.launched, <String>['emulator:Pixel_9']);
      expect(run.state.selectedDeviceId, 'emulator:Pixel_9');
      expect(startButton(tester).onPressed, isNull);
      expect(find.text('Starting the emulator…'), findsOneWidget);
      expect(find.text('Not running'), findsNothing);
      await finish(tester);
    });

    testWidgets('a failed launch shows an error with a retry instead of the progress', (
      tester,
    ) async {
      await pumpTab(tester);
      fake.set(const <Device>[_macos, _pixelEmulator]);
      await tester.pump(const Duration(milliseconds: 20));
      run.choose(deviceId: 'macos');
      await tester.pump();
      fake.launchError = Exception('no emulator');

      await tester.tap(find.text('macOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pixel 9'));
      await tester.pumpAndSettle();

      expect(find.text('Could not start the emulator'), findsOneWidget);
      expect(find.text('Starting the emulator…'), findsNothing);
      expect(startButton(tester).onPressed, isNull, reason: 'still not a running device');

      fake.launchError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(fake.launched, <String>['emulator:Pixel_9', 'emulator:Pixel_9']);
      expect(find.text('Starting the emulator…'), findsOneWidget);
      expect(find.text('Could not start the emulator'), findsNothing);
      await finish(tester);
    });

    testWidgets('choosing a device that is already launching does not launch it twice', (
      tester,
    ) async {
      await pumpTab(tester);
      fake.set(const <Device>[_macos, _pixelEmulator]);
      await tester.pump(const Duration(milliseconds: 20));
      run.choose(deviceId: 'macos');
      await tester.pump();

      await tester.tap(find.text('macOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pixel 9'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pixel 9'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pixel 9').last);
      await tester.pumpAndSettle();

      expect(fake.launched, <String>['emulator:Pixel_9']);
      expect(find.text('Starting the emulator…'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('choosing a running device launches nothing', (tester) async {
      await pumpTab(tester);
      fake.set(const <Device>[_macos, _pixelEmulator]);
      await tester.pump(const Duration(milliseconds: 20));
      run.choose(deviceId: 'emulator:Pixel_9');
      await tester.pump();

      await tester.tap(find.text('Pixel 9'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('macOS'));
      await tester.pumpAndSettle();

      expect(fake.launched, isEmpty);
      expect(startButton(tester).onPressed, isNotNull);
      expect(find.text('Starting the emulator…'), findsNothing);
      await finish(tester);
    });

    testWidgets('the error states fit a 340 px pane', (tester) async {
      await pumpTab(
        tester,
        repository: _FailingDevicesRepository(const FlutterNotFoundException()),
        width: 340,
        size: const Size(900, 600),
      );

      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  });

  group('in the right pane', () {
    late Dependencies dependencies;
    late MemoryDevicesRepository fakeDevices;

    setUp(() {
      fakeDevices = MemoryDevicesRepository(step: const Duration(milliseconds: 1));
      dependencies = testDependencies(devicesRepository: fakeDevices);
    });

    /// The button of the right pane (the title bar has buttons with the same tooltips).
    Finder inPane(String tooltip) =>
        find.descendant(of: find.byType(WorkspaceRightPane), matching: find.byTooltip(tooltip));

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<WorkspaceConfigWidgetState> pump(
      WidgetTester tester, {
      Size? size,
      bool openRunTab = true,
    }) async {
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
      if (openRunTab) state.dataController.selectPaneTab(RightPaneTab.run);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      return state;
    }

    testWidgets('the window picks the first running device even if the Run tab is never opened', (
      tester,
    ) async {
      final state = await pump(tester, openRunTab: false);
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byType(RunTab), findsNothing);
      expect(state.runController.state.projectId, isNotNull);
      expect(state.runController.state.selectedDeviceId, 'ios-sim-16-pro');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a device the user chose is not replaced by a later devices update', (
      tester,
    ) async {
      final state = await pump(tester, openRunTab: false);
      await tester.pump(const Duration(milliseconds: 20));
      state.runController.choose(deviceId: 'macos');

      state.devicesController.watch();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 20));

      expect(state.devicesController.state, isA<Devices$CompletedState>());
      expect(state.runController.state.selectedDeviceId, 'macos');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a booted emulator replaces the available entry the user chose', (tester) async {
      final state = await pump(tester, openRunTab: false);
      fakeDevices.set(const <Device>[_macos, _pixelEmulator]);
      await settle(tester);
      state.runController.choose(deviceId: 'emulator:Pixel_9');
      await tester.pump();

      fakeDevices.set(const <Device>[_macos, _pixelRunning]);
      await settle(tester);

      expect(state.runController.state.selectedDeviceId, 'emulator-5554');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the selected device leaving the list selects the first running one', (
      tester,
    ) async {
      final state = await pump(tester, openRunTab: false);
      fakeDevices.set(const <Device>[_macos, _pixelRunning]);
      await settle(tester);
      state.runController.choose(deviceId: 'emulator-5554');
      await tester.pump();

      fakeDevices.set(const <Device>[_macos]);
      await settle(tester);

      expect(state.runController.state.selectedDeviceId, 'macos');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('no running device left clears the selection', (tester) async {
      final state = await pump(tester, openRunTab: false);
      fakeDevices.set(const <Device>[_macos]);
      await settle(tester);
      expect(state.runController.state.selectedDeviceId, 'macos');

      fakeDevices.set(const <Device>[_pixelEmulator]);
      await settle(tester);

      expect(state.runController.state.selectedDeviceId, isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('an available device the user chose stays chosen while it boots', (tester) async {
      final state = await pump(tester, openRunTab: false);
      fakeDevices.set(const <Device>[_macos, _pixelEmulator]);
      await settle(tester);
      state.runController.choose(deviceId: 'emulator:Pixel_9');
      await tester.pump();

      fakeDevices.set(const <Device>[_macos, _pixelEmulator]);
      await settle(tester);

      expect(state.runController.state.selectedDeviceId, 'emulator:Pixel_9');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the title bar chip launches an available device and disables Run', (tester) async {
      final state = await pump(tester, openRunTab: false);
      fakeDevices.set(const <Device>[_macos, _pixelEmulator]);
      await settle(tester);

      await tester.tap(find.text('macOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pixel 9'));
      await tester.pumpAndSettle();

      expect(fakeDevices.launched, <String>['emulator:Pixel_9']);
      expect(state.runController.state.selectedDeviceId, 'emulator:Pixel_9');
      expect(state.runLink.canStart, isFalse);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('an available device is not picked as the default', (tester) async {
      final state = await pump(tester, openRunTab: false);
      fakeDevices.set(const <Device>[_pixelEmulator]);
      await settle(tester);

      expect(state.runController.state.selectedDeviceId, isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('an error in the run puts a badge on the tab', (tester) async {
      await pump(tester);
      expect(find.text('Not running'), findsOneWidget);

      await tester.tap(inPane('Run'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(inPane('Hot reload'));
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('Layout overflow'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(WorkspaceRightPane), matching: find.text('1')),
        findsOneWidget,
        reason: 'the badge of the Run tab',
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('picking a widget shows its card', (tester) async {
      await pump(tester);
      await tester.tap(inPane('Run'));
      await tester.pump(const Duration(milliseconds: 20));

      await tester.tap(find.byTooltip('Pick a widget in the app'));
      await tester.pump();
      expect(find.text('Tap a widget in the running app…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('Tap a widget in the running app…'), findsNothing);
      expect(find.text('BookingCard'), findsWidgets);
      expect(find.text('booking_card.dart:42:7'), findsOneWidget);
      expect(find.text('BookingList'), findsOneWidget);
      expect(find.text('BookingScreen'), findsOneWidget);
      expect(find.text('Add to message'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the picked widget survives a later action', (tester) async {
      final state = await pump(tester);
      await tester.tap(inPane('Run'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byTooltip('Pick a widget in the app'));
      await tester.pump(const Duration(milliseconds: 20));

      await tester.tap(inPane('Hot reload'));
      await tester.pump(const Duration(milliseconds: 20));

      expect(state.runActionsController.pick.value.widget, isA<PickedWidget>());
      expect(find.text('booking_card.dart:42:7'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('900×600 with the run tab does not overflow', (tester) async {
      final state = await pump(tester, size: const Size(900, 600));
      state.toggleRightPane(windowWidth: 900);
      await settle(tester);
      await tester.pump();
      await tester.pump();
      await tester.tap(inPane('Run'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(inPane('Hot reload'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byTooltip('Pick a widget in the app'));
      await tester.pump(const Duration(milliseconds: 20));

      expect(tester.takeException(), isNull);
      await disposeTestApp(tester, dependencies);
    });
  });
}
