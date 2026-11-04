import 'dart:async';
import 'dart:io' as io;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_config_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/launch_config_reader.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/launch_config.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_start_arguments.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/memory_devices_repository.dart';
import '../../support/memory_run_config_repository.dart';
import '../../support/scripted_app_run_repository.dart';
import '../../support/scripted_widget_picker_repository.dart';

const Device _macos = Device(
  id: 'macos',
  name: 'macOS',
  platform: DevicePlatform.macos,
  kind: DeviceKind.running,
);

const _step = Duration(milliseconds: 1);

/// A repository that emits exactly what a test pushes.
final class _ScriptedRunRepository implements IAppRunRepository {
  final Map<int, StreamController<LogEntry>> _logs = <int, StreamController<LogEntry>>{};
  final Map<int, StreamController<RunState>> _states = <int, StreamController<RunState>>{};

  /// The `(project, seq)` pairs `markSent` was called with.
  final List<(int, int)> marked = <(int, int)>[];

  @override
  RunState currentRun(int projectId) => const RunIdle();

  @override
  List<LogEntry> recentLogs(int projectId, {int limit = kRunLogLimit}) => const <LogEntry>[];

  @override
  bool get isPreview => true;

  StreamController<LogEntry> _logsOf(int project) =>
      _logs.putIfAbsent(project, StreamController<LogEntry>.broadcast);

  StreamController<RunState> _statesOf(int project) =>
      _states.putIfAbsent(project, StreamController<RunState>.broadcast);

  void emit(int project, LogEntry entry) => _logsOf(project).add(entry);

  void emitState(int project, RunState state) => _statesOf(project).add(state);

  /// Lines replayed to a new `logs` listener, per project.
  final Map<int, List<LogEntry>> replay = <int, List<LogEntry>>{};

  @override
  Stream<LogEntry> logs(int projectId) {
    final live = _logsOf(projectId).stream;
    final buffered = replay[projectId] ?? const <LogEntry>[];
    return (() async* {
      for (final entry in buffered) {
        yield entry;
      }
      yield* live;
    })();
  }

  @override
  Stream<RunState> watchRun(int projectId) => _statesOf(projectId).stream;

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
  Future<void> markSent(int projectId, int seq) async => marked.add((projectId, seq));

  /// The projects `stop` was called for.
  final List<int> stops = <int>[];

  @override
  Future<void> stop(int projectId) async => stops.add(projectId);

  /// The projects `hotReload` was called for.
  final List<int> reloads = <int>[];

  /// The projects `hotRestart` was called for.
  final List<int> restarts = <int>[];

  @override
  Future<Duration> hotReload(int projectId) async {
    reloads.add(projectId);
    return Duration.zero;
  }

  @override
  Future<Duration> hotRestart(int projectId) async {
    restarts.add(projectId);
    return Duration.zero;
  }

  @override
  Future<void> openDevTools(int projectId) async {}

  /// When set, `screenshot` waits for it (a shot that hangs).
  Completer<String?>? screenshotGate;

  @override
  Future<String?> screenshot(int projectId) async => screenshotGate?.future;

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
      controller = RunController(
        repository: scripted,
        configRepository: MemoryRunConfigRepository(),
      );
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
      final fake = ScriptedAppRunRepository(step: _step);
      addTearDown(fake.dispose);
      final fakeController = RunController(
        repository: fake,
        configRepository: MemoryRunConfigRepository(),
      )..watch(1);
      addTearDown(fakeController.dispose);
      await pumpEventQueue();
      await fake.start(1, device: _macos, mode: BuildMode.debug, target: 'lib/main.dart');
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

    test('clearDevice forgets the chosen device', () async {
      controller.watch(1);
      await pumpEventQueue();
      controller
        ..choose(deviceId: 'macos')
        ..clearDevice();

      expect(controller.state.selectedDeviceId, isNull);
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

    test(
      'clearLogs empties the logs and the error count, and the cleared lines stay away',
      () async {
        controller.watch(1);
        await pumpEventQueue();
        scripted
          ..emit(1, _entry(0, level: LogLevel.error))
          ..emit(1, _entry(1));
        await pumpEventQueue();

        controller.clearLogs();
        expect(controller.state.logs, isEmpty);
        expect(controller.state.errorCount, 0);

        scripted.emit(1, _entry(2));
        await pumpEventQueue();
        expect(controller.state.logs.map((log) => log.seq), <int>[2]);

        // A replay after a project switch does not bring the cleared lines back.
        controller.watch(2);
        await pumpEventQueue();
        scripted.replay[1] = <LogEntry>[_entry(0, level: LogLevel.error), _entry(1), _entry(2)];
        controller.watch(1);
        await pumpEventQueue();
        expect(controller.state.logs.map((log) => log.seq), <int>[2]);
      },
    );

    test('coming back to a running project restores its logs, error and sent flags', () async {
      final fake = ScriptedAppRunRepository(step: _step);
      addTearDown(fake.dispose);
      final fakeController = RunController(
        repository: fake,
        configRepository: MemoryRunConfigRepository(),
      )..watch(1);
      addTearDown(fakeController.dispose);
      await pumpEventQueue();
      await fake.start(1, device: _macos, mode: BuildMode.debug, target: 'lib/main.dart');
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

  group('RunController arguments', () {
    late _ScriptedRunRepository scripted;
    late MemoryRunConfigRepository config;
    late RunController controller;

    setUp(() {
      scripted = _ScriptedRunRepository();
      config = MemoryRunConfigRepository(
        initial: <int, RunArguments>{
          1: const RunArguments(flavor: 'dev'),
          2: const RunArguments(dartDefines: <String>['A=1']),
        },
      );
      controller = RunController(repository: scripted, configRepository: config);
    });

    tearDown(() async {
      controller.dispose();
      await scripted.dispose();
    });

    test('follow the saved arguments of the project and change with them', () async {
      controller.watch(1);
      await pumpEventQueue();
      expect(controller.state.arguments, const RunArguments(flavor: 'dev'));

      await config.save(1, const RunArguments(flavor: 'prod'));
      await pumpEventQueue();
      expect(controller.state.arguments, const RunArguments(flavor: 'prod'));
    });

    test('belong to the project: a switch brings the other project\'s arguments', () async {
      controller.watch(1);
      await pumpEventQueue();
      controller.watch(2);
      await pumpEventQueue();
      expect(controller.state.arguments, const RunArguments(dartDefines: <String>['A=1']));

      await config.save(1, const RunArguments(flavor: 'late'));
      await pumpEventQueue();
      expect(
        controller.state.arguments,
        const RunArguments(dartDefines: <String>['A=1']),
        reason: 'a save for the project that was left changes nothing',
      );
    });

    test('a start after a save carries the saved flavor', () async {
      final repository = ScriptedAppRunRepository(step: _step);
      addTearDown(repository.dispose);
      final run = RunController(repository: repository, configRepository: config)..watch(1);
      addTearDown(run.dispose);
      final actions = RunActionsController(
        runRepository: repository,
        pickerRepository: ScriptedWidgetPickerRepository(step: _step),
      );
      addTearDown(actions.dispose);
      await pumpEventQueue();

      actions.start(
        1,
        device: _macos,
        mode: run.state.mode,
        arguments: () => run.startArgumentsFor(1),
      );
      await Future<void>.delayed(_step * 50);

      expect(repository.starts.single.arguments.toFlutterArgs(), <String>['--flavor', 'dev']);
    });

    test(
      'Default starts with the saved arguments and the target, without reading launch.json',
      () async {
        controller.watch(1);
        await pumpEventQueue();
        controller.choose(target: 'lib/main_dev.dart');
        final reads = config.launchReads.length;

        expect(
          await controller.startArgumentsFor(1),
          const RunStartArguments(
            target: 'lib/main_dev.dart',
            arguments: RunArguments(flavor: 'dev'),
          ),
        );
        expect(config.launchReads, hasLength(reads));
      },
    );
  });

  group('RunController configurations', () {
    late _ScriptedRunRepository scripted;
    late MemoryRunConfigRepository config;
    late RunController controller;

    const web = LaunchConfig(
      name: 'Web',
      target: 'lib/main_web.dart',
      deviceId: 'web-server',
      mode: BuildMode.release,
    );
    const prod = LaunchConfig(
      name: 'Prod',
      target: 'lib/main_prod.dart',
      flavor: 'prod',
      dartDefines: <String>['API=https://prod'],
      extraArgs: '--dart-define-from-file=config/avera/production.json',
      environment: <String, String>{'SENTRY': 'on'},
    );

    setUp(() {
      scripted = _ScriptedRunRepository();
      config = MemoryRunConfigRepository(
        initial: <int, RunArguments>{
          1: const RunArguments(flavor: 'dev', dartDefines: <String>['X=1'], extraArgs: '-v'),
        },
        launch: <int, LaunchConfigs>{
          1: const LaunchConfigsRead(<LaunchConfig>[web, prod]),
        },
      );
      controller = RunController(repository: scripted, configRepository: config);
    });

    tearDown(() async {
      controller.dispose();
      await scripted.dispose();
    });

    test('watch reads launch.json and the stored selection of the project', () async {
      config = MemoryRunConfigRepository(
        selected: <int, String>{1: 'Prod'},
        launch: <int, LaunchConfigs>{
          1: const LaunchConfigsRead(<LaunchConfig>[web, prod]),
        },
      );
      final run = RunController(repository: scripted, configRepository: config)..watch(1);
      addTearDown(run.dispose);
      await pumpEventQueue();

      expect(run.state.selectedConfig, 'Prod');
      expect((run.state.launchConfigs! as LaunchConfigsRead).configs, <LaunchConfig>[web, prod]);
    });

    test('choosing a config with a device switches the device chip', () async {
      controller.watch(1);
      await pumpEventQueue();
      controller
        ..choose(deviceId: 'macos')
        ..chooseConfig('Web');
      await pumpEventQueue();

      expect(controller.state.selectedConfig, 'Web');
      expect(controller.state.selectedDeviceId, 'web-server');
      expect(controller.state.mode, BuildMode.release);
      expect(config.savedSelections, <(int, String?)>[(1, 'Web')]);
    });

    test('a config without a device or mode keeps the chips', () async {
      controller.watch(1);
      await pumpEventQueue();
      controller
        ..choose(deviceId: 'macos', mode: BuildMode.profile)
        ..chooseConfig('Prod');
      await pumpEventQueue();

      expect(controller.state.selectedDeviceId, 'macos');
      expect(controller.state.mode, BuildMode.profile);
    });

    test('the chip stays switchable after choosing', () async {
      controller.watch(1);
      await pumpEventQueue();
      controller.chooseConfig('Web');
      await pumpEventQueue();

      controller.choose(deviceId: 'macos', mode: BuildMode.debug);

      expect(controller.state.selectedDeviceId, 'macos');
      expect(controller.state.mode, BuildMode.debug);
      expect(controller.state.selectedConfig, 'Web', reason: 'the chips do not undo the choice');
      expect((await controller.startArgumentsFor(1)).target, 'lib/main_web.dart');
    });

    test('choosing Default stores null', () async {
      controller.watch(1);
      await pumpEventQueue();
      controller.chooseConfig('Prod');
      await pumpEventQueue();

      controller.chooseConfig(null);
      await pumpEventQueue();

      expect(controller.state.selectedConfig, isNull);
      expect(config.savedSelections.last, (1, null));
    });

    test('a vanished config falls back to Default', () async {
      config = MemoryRunConfigRepository(
        selected: <int, String>{1: 'Gone'},
        launch: <int, LaunchConfigs>{
          1: const LaunchConfigsRead(<LaunchConfig>[prod]),
        },
      );
      final run = RunController(repository: scripted, configRepository: config)..watch(1);
      addTearDown(run.dispose);
      await pumpEventQueue();

      expect(run.state.selectedConfig, isNull);
      expect(config.savedSelections, <(int, String?)>[(1, null)]);
    });

    test('a config removed from the file before a start runs Default and saves it', () async {
      controller.watch(1);
      await pumpEventQueue();
      controller.chooseConfig('Prod');
      await pumpEventQueue();

      config.launch[1] = const LaunchConfigsRead(<LaunchConfig>[web]);
      final start = await controller.startArgumentsFor(1);

      expect(
        start,
        const RunStartArguments(
          arguments: RunArguments(flavor: 'dev', dartDefines: <String>['X=1'], extraArgs: '-v'),
        ),
      );
      expect(controller.state.selectedConfig, isNull);
      expect(config.savedSelections.last, (1, null));
    });

    test('a deleted launch.json falls back to Default', () async {
      controller.watch(1);
      await pumpEventQueue();
      controller.chooseConfig('Prod');
      await pumpEventQueue();

      config.launch.remove(1);
      await controller.refreshConfigs();

      expect(controller.state.launchConfigs, isA<LaunchConfigsMissing>());
      expect(controller.state.selectedConfig, isNull);
      expect(config.savedSelections.last, (1, null));
    });

    test('an unreadable launch.json keeps the choice and refuses the start', () async {
      controller.watch(1);
      await pumpEventQueue();
      controller.chooseConfig('Prod');
      await pumpEventQueue();

      config.launch[1] = const LaunchConfigsUnreadable(LaunchUnreadableKind.invalidJson, 'oops');
      await controller.refreshConfigs();
      expect(controller.state.selectedConfig, 'Prod');

      await expectLater(
        controller.startArgumentsFor(1),
        throwsA(
          isA<RunConfigNotStartable>()
              .having((error) => error.name, 'name', 'Prod')
              .having((error) => error.unreadable?.detail, 'unreadable', 'oops'),
        ),
      );
      expect(controller.state.selectedConfig, 'Prod');
    });

    test('an unsupported config is refused with its reason', () async {
      const home = LaunchConfig(
        name: 'Home',
        unsupported: LaunchUnsupportedVariable(r'${env:HOME}'),
      );
      config.launch[1] = const LaunchConfigsRead(<LaunchConfig>[home]);
      controller.watch(1);
      await pumpEventQueue();
      controller.chooseConfig('Home');
      await pumpEventQueue();

      await expectLater(
        controller.startArgumentsFor(1),
        throwsA(
          isA<RunConfigNotStartable>().having(
            (error) => error.unsupported,
            'unsupported',
            const LaunchUnsupportedVariable(r'${env:HOME}'),
          ),
        ),
      );
    });

    test('two configs with the same name use the first', () async {
      const first = LaunchConfig(name: 'Dup', flavor: 'a', deviceId: 'macos');
      const second = LaunchConfig(name: 'Dup', flavor: 'b', deviceId: 'chrome');
      config.launch[1] = const LaunchConfigsRead(<LaunchConfig>[first, second]);
      controller.watch(1);
      await pumpEventQueue();

      controller.chooseConfig('Dup');
      await pumpEventQueue();

      expect(controller.state.selectedDeviceId, 'macos');
      expect((await controller.startArgumentsFor(1)).arguments.flavor, 'a');
    });

    test('refreshConfigs reads the file of the current project again', () async {
      controller.watch(1);
      await pumpEventQueue();
      config.launch[1] = const LaunchConfigsRead(<LaunchConfig>[prod]);

      await controller.refreshConfigs();

      expect((controller.state.launchConfigs! as LaunchConfigsRead).configs, <LaunchConfig>[prod]);
    });

    test('a switch of project brings that project\'s selection and file', () async {
      config
        ..launch[2] = const LaunchConfigsRead(<LaunchConfig>[web])
        ..launch[1] = const LaunchConfigsRead(<LaunchConfig>[prod]);
      await config.saveSelected(2, 'Web');
      controller.watch(1);
      await pumpEventQueue();
      controller.chooseConfig('Prod');
      await pumpEventQueue();

      controller.watch(2);
      await pumpEventQueue();

      expect(controller.state.selectedConfig, 'Web');
      expect((controller.state.launchConfigs! as LaunchConfigsRead).configs, <LaunchConfig>[web]);
    });

    test(
      'a config run passes its flavor, defines, extra args and target, not the Default args',
      () async {
        final repository = ScriptedAppRunRepository(step: _step);
        addTearDown(repository.dispose);
        final run = RunController(repository: repository, configRepository: config)..watch(1);
        addTearDown(run.dispose);
        final actions = RunActionsController(
          runRepository: repository,
          pickerRepository: ScriptedWidgetPickerRepository(step: _step),
        );
        addTearDown(actions.dispose);
        await pumpEventQueue();
        run.chooseConfig('Prod');
        await pumpEventQueue();

        actions.start(
          1,
          device: _macos,
          mode: run.state.mode,
          arguments: () => run.startArgumentsFor(1),
        );
        await Future<void>.delayed(_step * 50);

        final start = repository.starts.single;
        expect(start.target, 'lib/main_prod.dart');
        expect(start.arguments.toFlutterArgs(), <String>[
          '--flavor',
          'prod',
          '--dart-define',
          'API=https://prod',
          '--dart-define-from-file=config/avera/production.json',
        ]);
        expect(start.environment, <String, String>{'SENTRY': 'on'});
      },
    );
  });

  group('RunController with launch.json on disk', () {
    test('editing launch.json between starts uses the new args', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final root = io.Directory.systemTemp.createTempSync('run_controller_test');
      addTearDown(() => root.deleteSync(recursive: true));
      final project = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: root.path, name: 'app'));
      final file = io.File(p.join(root.path, '.vscode', 'launch.json'))
        ..createSync(recursive: true);
      void writeLaunch(String flavor) => file.writeAsStringSync('''
{
  // The project's run configurations.
  "configurations": [
    {"name": "Prod", "type": "dart", "request": "launch", "args": ["--flavor", "$flavor"],},
  ],
}''');
      writeLaunch('prod');

      final repository = ScriptedAppRunRepository(step: _step);
      addTearDown(repository.dispose);
      final run = RunController(
        repository: repository,
        configRepository: RunConfigRepositoryImpl(database: database),
      )..watch(project);
      addTearDown(run.dispose);
      final actions = RunActionsController(
        runRepository: repository,
        pickerRepository: ScriptedWidgetPickerRepository(step: _step),
      );
      addTearDown(actions.dispose);
      await pumpEventQueue();
      run.chooseConfig('Prod');
      await pumpEventQueue();

      void start() => actions.start(
        project,
        device: _macos,
        mode: BuildMode.debug,
        arguments: () => run.startArgumentsFor(project),
      );
      start();
      await Future<void>.delayed(_step * 50);

      // Edited while the menu is closed: no refreshConfigs, nothing reopened.
      writeLaunch('staging');
      start();
      await Future<void>.delayed(_step * 50);

      expect(repository.starts.map((start) => start.arguments.flavor), <String?>[
        'prod',
        'staging',
      ]);
    });
  });

  group('RunConfigController', () {
    test('save stores the arguments and completes', () async {
      final repository = MemoryRunConfigRepository();
      final controller = RunConfigController(repository: repository);
      addTearDown(controller.dispose);

      controller.save(1, const RunArguments(flavor: 'dev'));
      expect(controller.state, isA<RunConfig$InProgressState>());
      await pumpEventQueue();

      expect(controller.state, isA<RunConfig$CompletedState>());
      expect(repository.saved.single, (1, const RunArguments(flavor: 'dev')));
    });

    test('a failed save is an error state', () async {
      final repository = MemoryRunConfigRepository()..saveError = Exception('no');
      final controller = RunConfigController(repository: repository);
      addTearDown(controller.dispose);

      controller.save(1, const RunArguments());
      await pumpEventQueue();

      expect(controller.state, isA<RunConfig$ErrorState>());
    });

    test('drops a save made while another is in progress', () async {
      final repository = MemoryRunConfigRepository();
      final controller = RunConfigController(repository: repository);
      addTearDown(controller.dispose);

      controller
        ..save(1, const RunArguments(flavor: 'a'))
        ..save(1, const RunArguments(flavor: 'b'));
      await pumpEventQueue();

      expect(repository.saved.map((e) => e.$2.flavor), <String?>['a']);
    });
  });

  group('RunActionsController', () {
    test('start, reload and stop go to the repository and complete', () async {
      final repository = ScriptedAppRunRepository(step: _step);
      addTearDown(repository.dispose);
      final states = <RunState>[];
      final subscription = repository.watchRun(1).listen(states.add);
      addTearDown(subscription.cancel);
      final actions = RunActionsController(
        runRepository: repository,
        pickerRepository: ScriptedWidgetPickerRepository(step: _step),
      );
      addTearDown(actions.dispose);

      actions.start(
        1,
        device: _macos,
        mode: BuildMode.debug,
        arguments: () async => const RunStartArguments(),
      );
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

    test('a start whose arguments cannot be had is an error and starts nothing', () async {
      final repository = ScriptedAppRunRepository(step: _step);
      addTearDown(repository.dispose);
      final actions = RunActionsController(
        runRepository: repository,
        pickerRepository: ScriptedWidgetPickerRepository(step: _step),
      );
      addTearDown(actions.dispose);

      actions.start(
        1,
        device: _macos,
        mode: BuildMode.debug,
        arguments: () async => throw const RunConfigNotStartable.unsupported(
          'Home',
          LaunchUnsupportedVariable(r'${env:HOME}'),
        ),
      );
      await Future<void>.delayed(_step * 10);

      expect(repository.starts, isEmpty);
      expect(
        actions.state,
        isA<RunActions$ErrorState>().having(
          (state) => state.error,
          'error',
          isA<RunConfigNotStartable>(),
        ),
      );
    });

    group('picking', () {
      late _ScriptedRunRepository repository;
      late ScriptedWidgetPickerRepository picker;
      late RunActionsController actions;

      setUp(() {
        repository = _ScriptedRunRepository();
        // A pick waits until the test ends it, like a real one waits for a tap.
        picker = ScriptedWidgetPickerRepository(step: const Duration(hours: 1));
        actions = RunActionsController(runRepository: repository, pickerRepository: picker);
      });

      tearDown(() async {
        actions.dispose();
        await picker.dispose();
        await repository.dispose();
      });

      List<String> chain() => actions.pick.value.chain.map((link) => link.name).toList();

      test(
        'pickWidget waits outside the action handler and shows the widget with its chain',
        () async {
          actions.pickWidget(1);
          expect(actions.pick.value.picking, isTrue);
          expect(actions.pick.value.projectId, 1);
          expect(actions.isProcessing, isFalse, reason: 'a pick never blocks the other actions');

          picker.complete(1);
          await pumpEventQueue();

          final pick = actions.pick.value;
          expect(pick.picking, isFalse);
          expect(pick.widget, ScriptedWidgetPickerRepository.bookingCard);
          expect(chain(), <String>['BookingCard', 'BookingList', 'BookingScreen']);
          expect(pick.current, 0);
          expect(pick.problem, isNull);
        },
      );

      test('a second pickWidget while one waits is dropped', () async {
        actions
          ..pickWidget(1)
          ..pickWidget(1);
        await pumpEventQueue();

        expect(picker.picks, <int>[1]);
        actions.cancelPick(1);
      });

      test('a pick that gives no widget says why; a cancelled one keeps the last widget', () async {
        actions.pickWidget(1);
        picker.complete(1);
        await pumpEventQueue();

        actions.pickWidget(1);
        picker
          ..result = const PickCancelled()
          ..complete(1);
        await pumpEventQueue();
        expect(actions.pick.value.widget, ScriptedWidgetPickerRepository.bookingCard);
        expect(actions.pick.value.picking, isFalse);

        for (final result in <PickResult>[
          const PickNoProjectWidget(),
          const PickFailed(PickFailure.connectionLost),
        ]) {
          actions.pickWidget(1);
          picker
            ..result = result
            ..complete(1);
          await pumpEventQueue();

          expect(actions.pick.value.problem, result);
          expect(actions.pick.value.widget, isNull, reason: '$result');
          expect(actions.pick.value.picking, isFalse);
        }
      });

      test('a pick that throws fails with the error', () async {
        final failing = _ThrowingPicker();
        final other = RunActionsController(runRepository: repository, pickerRepository: failing);
        addTearDown(other.dispose);

        other.pickWidget(1);
        await pumpEventQueue();

        expect(other.pick.value.problem, isA<PickFailed>());
        expect((other.pick.value.problem! as PickFailed).kind, PickFailure.inspectorError);
        expect(other.pick.value.picking, isFalse);
      });

      test('cancelPick ends the pick at once and asks the picker to cancel', () async {
        actions
          ..pickWidget(1)
          ..cancelPick(1);

        expect(actions.pick.value.picking, isFalse);
        await pumpEventQueue();
        expect(picker.cancels, <int>[1]);

        actions.cancelPick(1);
        await pumpEventQueue();
        expect(picker.cancels, <int>[1], reason: 'nothing waits any more');
      });

      for (final (name, act, calls)
          in <(String, void Function(RunActionsController), List<int> Function())>[
            ('stop', (actions) => actions.stop(1), () => repository.stops),
            ('hot reload', (actions) => actions.hotReload(1), () => repository.reloads),
            ('hot restart', (actions) => actions.hotRestart(1), () => repository.restarts),
          ]) {
        test('$name while a pick waits runs at once and cancels the pick', () async {
          actions.pickWidget(1);
          await pumpEventQueue();

          act(actions);
          await pumpEventQueue();

          expect(calls(), <int>[1], reason: 'not dropped');
          expect(picker.cancels, <int>[1]);
          expect(actions.pick.value.picking, isFalse);
          expect(actions.state, isA<RunActions$CompletedState>());
        });
      }

      test('a hot reload that does not cancel the pick leaves the waiting pick alone', () async {
        actions.pickWidget(1);
        await pumpEventQueue();

        actions.hotReload(1, cancelPick: false);
        await pumpEventQueue();

        expect(repository.reloads, <int>[1]);
        expect(actions.pick.value.picking, isTrue);
        expect(picker.cancels, isEmpty);
        actions.cancelPick(1);
      });

      test('a screenshot while a pick waits leaves the pick alone', () async {
        actions
          ..pickWidget(1)
          ..screenshot(1);
        await pumpEventQueue();

        expect(actions.pick.value.picking, isTrue);
        expect(picker.cancels, isEmpty);
        actions.cancelPick(1);
      });

      test('a pick in another project cancels the waiting one', () async {
        actions
          ..pickWidget(1)
          ..pickWidget(2);
        await pumpEventQueue();

        expect(picker.cancels, <int>[1]);
        expect(actions.pick.value.projectId, 2);
        expect(actions.pick.value.picking, isTrue);
        actions.cancelPick(2);
      });

      test(
        'selectAncestor switches to the link, keeps the inner links and moves the highlight',
        () async {
          actions.pickWidget(1);
          picker.complete(1);
          await pumpEventQueue();

          const list = PickedWidget(
            name: 'BookingList',
            file: 'lib/booking_list.dart',
            line: 20,
            column: 5,
            id: 'inspector-list',
            ancestors: <PickedAncestor>[
              PickedAncestor(
                name: 'BookingScreen',
                file: 'lib/s.dart',
                line: 9,
                id: 'inspector-screen',
              ),
              PickedAncestor(name: 'App', file: 'lib/main.dart', line: 3, id: 'inspector-app'),
            ],
          );
          picker.selectResult = const PickPicked(list);
          actions.selectAncestor(1, 'inspector-list');
          await pumpEventQueue();

          expect(picker.selects, <(int, String)>[(1, 'inspector-list')]);
          expect(actions.pick.value.widget, list);
          expect(chain(), <String>['BookingCard', 'BookingList', 'BookingScreen', 'App']);
          expect(actions.pick.value.current, 1);
        },
      );

      test('selectAncestor of a released id says it is gone and keeps the card', () async {
        actions.pickWidget(1);
        picker.complete(1);
        await pumpEventQueue();

        picker.selectResult = const PickGone();
        actions.selectAncestor(1, 'inspector-screen');
        await pumpEventQueue();

        expect(actions.pick.value.problem, const PickGone());
        expect(actions.pick.value.widget, ScriptedWidgetPickerRepository.bookingCard);
        expect(actions.pick.value.current, 0);
      });

      test('dispose cancels a waiting pick; a result after it changes nothing', () async {
        RunActionsController(runRepository: repository, pickerRepository: picker)
          ..pickWidget(3)
          ..dispose();
        await pumpEventQueue();
        expect(picker.cancels, <int>[3]);

        // A picker that answers late, after the controller is gone (cancel does not end its pick).
        final latePicker = _LatePicker();
        RunActionsController(runRepository: repository, pickerRepository: latePicker)
          ..pickWidget(4)
          ..dispose();
        expect(latePicker.cancels, <int>[4]);
        latePicker.pending.complete(const PickPicked(ScriptedWidgetPickerRepository.bookingCard));
        await pumpEventQueue();
        // Reaching here without an uncaught error means the disposed notifier was not touched.
      });
    });

    test('stop is not dropped while another action hangs', () async {
      final repository = _ScriptedRunRepository()..screenshotGate = Completer<String?>();
      addTearDown(repository.dispose);
      final actions = RunActionsController(
        runRepository: repository,
        pickerRepository: ScriptedWidgetPickerRepository(step: _step),
      );
      addTearDown(actions.dispose);

      actions.screenshot(1);
      await pumpEventQueue();
      expect(actions.isProcessing, isTrue);
      actions.stop(1);
      await pumpEventQueue();

      expect(repository.stops, <int>[1]);
      repository.screenshotGate!.complete(null);
      await pumpEventQueue();
      expect(actions.state, isA<RunActions$CompletedState>());
    });

    test('drops a second action while one is in progress', () async {
      final repository = _ScriptedRunRepository()..screenshotGate = Completer<String?>();
      addTearDown(repository.dispose);
      final actions = RunActionsController(
        runRepository: repository,
        pickerRepository: ScriptedWidgetPickerRepository(step: _step),
      );
      addTearDown(actions.dispose);

      actions
        ..screenshot(1)
        ..hotReload(1);
      repository.screenshotGate!.complete(null);
      await pumpEventQueue();

      expect(repository.reloads, isEmpty);
      expect(actions.state, isA<RunActions$CompletedState>());
    });
  });

  group('DevicesController', () {
    test('completes with the devices', () async {
      final controller = DevicesController(repository: MemoryDevicesRepository(step: _step))
        ..watch();
      addTearDown(controller.dispose);
      expect(controller.state, isA<Devices$InProgressState>());

      await Future<void>.delayed(_step * 50);

      final state = controller.state as Devices$CompletedState;
      expect(state.devices, hasLength(5));
    });
  });
}

/// A picker whose every call fails.
final class _ThrowingPicker implements IWidgetPickerRepository {
  @override
  Future<PickResult> pick(int projectId) async => throw StateError('broken');

  @override
  Future<void> cancel(int projectId) async {}

  @override
  Future<PickResult> select(int projectId, String id) async => throw StateError('broken');

  @override
  Future<void> dispose() async {}
}

/// A picker whose pick ends only when the test completes [pending]; `cancel` is only recorded.
final class _LatePicker implements IWidgetPickerRepository {
  final Completer<PickResult> pending = Completer<PickResult>();
  final List<int> cancels = <int>[];

  @override
  Future<PickResult> pick(int projectId) => pending.future;

  @override
  Future<void> cancel(int projectId) async => cancels.add(projectId);

  @override
  Future<PickResult> select(int projectId, String id) async => const PickGone();

  @override
  Future<void> dispose() async {}
}
