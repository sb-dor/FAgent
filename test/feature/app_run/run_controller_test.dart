import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _step = Duration(milliseconds: 1);

/// A repository that emits exactly what a test pushes.
final class _ScriptedRunRepository implements IAppRunRepository {
  final Map<int, StreamController<LogEntry>> _logs = <int, StreamController<LogEntry>>{};
  final Map<int, StreamController<RunState>> _states = <int, StreamController<RunState>>{};

  /// The `(project, seq)` pairs `markSent` was called with.
  final List<(int, int)> marked = <(int, int)>[];

  @override
  bool get isPreview => true;

  StreamController<LogEntry> _logsOf(int project) =>
      _logs.putIfAbsent(project, StreamController<LogEntry>.broadcast);

  StreamController<RunState> _statesOf(int project) =>
      _states.putIfAbsent(project, StreamController<RunState>.broadcast);

  void emit(int project, LogEntry entry) => _logsOf(project).add(entry);

  void emitState(int project, RunState state) => _statesOf(project).add(state);

  @override
  Stream<LogEntry> logs(int projectId) => _logsOf(projectId).stream;

  @override
  Stream<RunState> watchRun(int projectId) => _statesOf(projectId).stream;

  @override
  Future<void> start(
    int projectId, {
    required String deviceId,
    required BuildMode mode,
    required String target,
  }) async {}

  @override
  Future<void> markSent(int projectId, int seq) async => marked.add((projectId, seq));

  @override
  Future<void> stop(int projectId) async {}

  @override
  Future<Duration> hotReload(int projectId) async => Duration.zero;

  @override
  Future<void> hotRestart(int projectId) async {}

  @override
  Future<void> dispose() async {
    for (final controller in <StreamController<Object?>>[..._logs.values, ..._states.values]) {
      await controller.close();
    }
  }
}

LogEntry _entry(int seq, {LogLevel level = LogLevel.info}) =>
    LogEntry(seq: seq, time: DateTime(2026, 10, 30), level: level, text: 'line $seq');

void main() {
  group('RunController', () {
    late _ScriptedRunRepository scripted;
    late RunController controller;

    setUp(() {
      scripted = _ScriptedRunRepository();
      controller = RunController(repository: scripted);
    });

    tearDown(() async {
      controller.dispose();
      await scripted.dispose();
    });

    test('logs keep only the newest 2000 entries', () async {
      controller.watch(1);
      await pumpEventQueue();

      // The first 100 lines are errors; they fall out of the window.
      for (var i = 0; i < 2500; i++) {
        scripted.emit(1, _entry(i, level: i < 100 ? LogLevel.error : LogLevel.info));
      }
      scripted.emit(1, _entry(2500, level: LogLevel.error));
      await pumpEventQueue();

      expect(kRunLogLimit, 2000);
      final logs = controller.state.logs;
      expect(logs, hasLength(2000));
      expect(logs.first.seq, 501);
      expect(logs.last.seq, 2500);
      expect(controller.state.errorCount, 1);
    });

    test('the run state follows the repository', () async {
      controller.watch(1);
      await pumpEventQueue();
      expect(controller.state.projectId, 1);
      expect(controller.state.run, isA<RunIdle>());

      scripted.emitState(1, const RunBuilding(progress: 0.2, label: 'Resolving dependencies'));
      await pumpEventQueue();

      expect(
        controller.state.run,
        const RunBuilding(progress: 0.2, label: 'Resolving dependencies'),
      );
    });

    test('switching projects drops the old run and logs', () async {
      final fake = FakeAppRunRepositoryImpl(step: _step);
      addTearDown(fake.dispose);
      final fakeController = RunController(repository: fake)..watch(1);
      addTearDown(fakeController.dispose);
      await pumpEventQueue();
      await fake.start(1, deviceId: 'macos', mode: BuildMode.debug, target: 'lib/main.dart');
      await Future<void>.delayed(_step * 50);
      expect(fakeController.state.run, isA<RunRunning>());
      expect(fakeController.state.logs, isNotEmpty);

      fakeController.watch(2);
      await pumpEventQueue();

      expect(fakeController.state.projectId, 2);
      expect(fakeController.state.run, isA<RunIdle>());
      expect(fakeController.state.logs, isEmpty);

      await fake.hotReload(1);
      await Future<void>.delayed(_step * 50);

      expect(fakeController.state.projectId, 2);
      expect(fakeController.state.run, isA<RunIdle>());
      expect(fakeController.state.logs, isEmpty);
    });

    test('events of the old project never reach the new one', () async {
      controller.watch(1);
      await pumpEventQueue();
      controller.watch(2);
      await pumpEventQueue();

      scripted
        ..emit(1, _entry(0, level: LogLevel.error))
        ..emitState(1, const RunStopped())
        ..emit(2, _entry(0));
      await pumpEventQueue();

      expect(controller.state.logs.map((log) => log.level), <LogLevel>[LogLevel.info]);
      expect(controller.state.run, isA<RunIdle>());
      expect(controller.state.errorCount, 0);
    });

    test('watching the same project again keeps its logs', () async {
      controller.watch(1);
      await pumpEventQueue();
      scripted.emit(1, _entry(0));
      await pumpEventQueue();

      controller.watch(1);
      await pumpEventQueue();

      expect(controller.state.logs, hasLength(1));
    });

    test(
      'choose changes the device, the mode and the target; a project switch keeps only the device',
      () async {
        controller.watch(1);
        await pumpEventQueue();
        expect(controller.state.selectedDeviceId, isNull);
        expect(controller.state.mode, BuildMode.debug);

        controller
          ..choose(deviceId: 'macos')
          ..choose(mode: BuildMode.release)
          ..choose(target: 'lib/main_dev.dart')
          ..watch(2);
        await pumpEventQueue();

        expect(controller.state.selectedDeviceId, 'macos');
        expect(controller.state.mode, BuildMode.debug);
        expect(controller.state.target, 'lib/main.dart');
      },
    );

    test('choose sets the mode and the target of the current project', () async {
      controller.watch(1);
      await pumpEventQueue();

      controller
        ..choose(mode: BuildMode.release)
        ..choose(target: 'lib/main_dev.dart');

      expect(controller.state.mode, BuildMode.release);
      expect(controller.state.target, 'lib/main_dev.dart');
    });

    test('markSent flags one log entry as sent to the agent', () async {
      controller.watch(1);
      await pumpEventQueue();
      scripted
        ..emit(1, _entry(0))
        ..emit(1, _entry(1));
      await pumpEventQueue();

      controller.markSent(1);

      expect(controller.state.logs.map((log) => log.sentToAgent), <bool>[false, true]);
      expect(scripted.marked, <(int, int)>[(1, 1)]);
    });

    test('coming back to a running project restores its logs, error and sent flags', () async {
      final fake = FakeAppRunRepositoryImpl(step: _step);
      addTearDown(fake.dispose);
      final fakeController = RunController(repository: fake)..watch(1);
      addTearDown(fakeController.dispose);
      await pumpEventQueue();
      await fake.start(1, deviceId: 'macos', mode: BuildMode.debug, target: 'lib/main.dart');
      await Future<void>.delayed(_step * 50);
      await fake.hotReload(1);
      await Future<void>.delayed(_step * 50);
      expect(fakeController.state.errorCount, 1);
      final before = fakeController.state.logs;
      fakeController.markSent(before.first.seq);
      await pumpEventQueue();

      fakeController.watch(2);
      await pumpEventQueue();
      expect(fakeController.state.logs, isEmpty);
      expect(fakeController.state.errorCount, 0);
      fakeController.watch(1);
      await pumpEventQueue();

      final after = fakeController.state;
      expect(after.projectId, 1);
      expect(after.run, isA<RunRunning>());
      expect(after.logs.map((log) => log.seq), before.map((log) => log.seq));
      expect(after.errorCount, 1);
      expect(after.logs.first.sentToAgent, isTrue);
      expect(after.logs.skip(1).any((log) => log.sentToAgent), isFalse);
    });
  });

  group('RunActionsController', () {
    test('start, reload and stop go to the repository and complete', () async {
      final repository = FakeAppRunRepositoryImpl(step: _step);
      addTearDown(repository.dispose);
      final states = <RunState>[];
      final subscription = repository.watchRun(1).listen(states.add);
      addTearDown(subscription.cancel);
      final actions = RunActionsController(
        runRepository: repository,
        pickerRepository: FakeWidgetPickerRepositoryImpl(step: _step),
      );
      addTearDown(actions.dispose);

      actions.start(1, deviceId: 'macos', mode: BuildMode.debug, target: 'lib/main.dart');
      await Future<void>.delayed(_step * 50);
      expect(states.last, isA<RunRunning>());
      expect(actions.state, isA<RunActions$CompletedState>());

      actions.hotReload(1);
      await Future<void>.delayed(_step * 50);
      expect((states.last as RunRunning).lastReload, isNotNull);

      actions.stop(1);
      await Future<void>.delayed(_step * 50);
      expect(states.last, isA<RunStopped>());
    });

    test('pickWidget completes with the picked widget', () async {
      final repository = FakeAppRunRepositoryImpl(step: _step);
      addTearDown(repository.dispose);
      final actions = RunActionsController(
        runRepository: repository,
        pickerRepository: FakeWidgetPickerRepositoryImpl(step: _step),
      );
      addTearDown(actions.dispose);

      actions.pickWidget(1);
      expect(actions.state, isA<RunActions$InProgressState>());
      await Future<void>.delayed(_step * 50);

      final state = actions.state as RunActions$CompletedState;
      expect(state.picked!.name, 'BookingCard');
    });

    test('drops a second action while one is in progress', () async {
      final repository = FakeAppRunRepositoryImpl(step: _step * 20);
      addTearDown(repository.dispose);
      final actions = RunActionsController(
        runRepository: repository,
        pickerRepository: FakeWidgetPickerRepositoryImpl(step: _step * 20),
      );
      addTearDown(actions.dispose);

      actions
        ..pickWidget(1)
        ..pickWidget(1);
      await Future<void>.delayed(_step * 200);

      expect(actions.state, isA<RunActions$CompletedState>());
    });
  });

  group('DevicesController', () {
    test('completes with the devices', () async {
      final controller = DevicesController(repository: FakeDevicesRepositoryImpl(step: _step))
        ..watch();
      addTearDown(controller.dispose);
      expect(controller.state, isA<Devices$InProgressState>());

      await Future<void>.delayed(_step * 50);

      final state = controller.state as Devices$CompletedState;
      expect(state.devices, hasLength(5));
    });
  });
}
