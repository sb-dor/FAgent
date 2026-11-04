import 'dart:async';

import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_run_link.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_run_config_repository.dart';
import '../../support/scripted_app_run_repository.dart';
import '../../support/scripted_widget_picker_repository.dart';

/// Replays the lines a test preloads.
final class _ScriptedRun implements IAppRunRepository {
  _ScriptedRun(this.lines);

  final List<LogEntry> lines;

  @override
  RunState currentRun(int projectId) => const RunIdle();

  @override
  List<LogEntry> recentLogs(int projectId, {int limit = kRunLogLimit}) => lines;

  @override
  bool get isPreview => false;

  @override
  Stream<LogEntry> logs(int projectId) => Stream<LogEntry>.fromIterable(lines);

  @override
  Stream<RunState> watchRun(int projectId) => Stream<RunState>.value(const RunIdle());

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
  Future<void> dispose() async {}
}

/// The fake run, counting the reloads and restarts it is asked for.
final class _CountingRun extends ScriptedAppRunRepository {
  _CountingRun({super.step});

  int reloadCalls = 0;
  int restartCalls = 0;

  @override
  Future<Duration> hotReload(int projectId) {
    reloadCalls++;
    return super.hotReload(projectId);
  }

  @override
  Future<Duration> hotRestart(int projectId) {
    restartCalls++;
    return super.hotRestart(projectId);
  }
}

void main() {
  /// The `@` offer of a run whose last line carries [error].
  Future<String?> errorMention(RunError error, {bool isPreview = false}) async {
    final repository = _ScriptedRun(<LogEntry>[
      LogEntry(
        seq: 0,
        time: DateTime(2026, 10, 30),
        level: LogLevel.error,
        text: error.title,
        error: error,
      ),
    ]);
    final data = WorkspaceDataController()..selectProject(1);
    final run = RunController(repository: repository, configRepository: MemoryRunConfigRepository())
      ..watch(1);
    final actions = RunActionsController(
      runRepository: repository,
      pickerRepository: ScriptedWidgetPickerRepository(),
    );
    final link = WorkspaceRunLink(
      data: data,
      run: run,
      actions: actions,
      reloadAfterTurn: () => false,
      isPreview: isPreview,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final text = link.mentions?.error?.text;
    link.dispose();
    actions.dispose();
    run.dispose();
    data.dispose();
    return text;
  }

  test('start passes the saved run arguments of the project', () async {
    final repository = ScriptedAppRunRepository(step: const Duration(milliseconds: 1));
    final config = MemoryRunConfigRepository(
      initial: <int, RunArguments>{1: const RunArguments(flavor: 'dev')},
    );
    const macos = Device(
      id: 'macos',
      name: 'macOS',
      platform: DevicePlatform.macos,
      kind: DeviceKind.running,
    );
    final data = WorkspaceDataController()..selectProject(1);
    final run = RunController(repository: repository, configRepository: config)..watch(1);
    final actions = RunActionsController(
      runRepository: repository,
      pickerRepository: ScriptedWidgetPickerRepository(),
    );
    final link = WorkspaceRunLink(
      data: data,
      run: run,
      actions: actions,
      reloadAfterTurn: () => false,
      selectedDevice: () => macos,
    );
    addTearDown(() async {
      link.dispose();
      actions.dispose();
      run.dispose();
      data.dispose();
      await repository.dispose();
    });
    await pumpEventQueue();

    link.start();
    await pumpEventQueue();

    expect(repository.starts.single.arguments, const RunArguments(flavor: 'dev'));
  });

  group('hot reload outside debug', () {
    const macos = Device(
      id: 'macos',
      name: 'macOS',
      platform: DevicePlatform.macos,
      kind: DeviceKind.running,
    );

    for (final mode in <BuildMode>[BuildMode.profile, BuildMode.release]) {
      test('a ${mode.name} run is never reloaded or restarted, not even after a turn', () async {
        final repository = _CountingRun(step: const Duration(milliseconds: 1));
        final data = WorkspaceDataController()..selectProject(1);
        final run = RunController(
          repository: repository,
          configRepository: MemoryRunConfigRepository(),
        )..watch(1);
        final actions = RunActionsController(
          runRepository: repository,
          pickerRepository: ScriptedWidgetPickerRepository(),
        );
        final link = WorkspaceRunLink(
          data: data,
          run: run,
          actions: actions,
          reloadAfterTurn: () => true,
          selectedDevice: () => macos,
        );
        addTearDown(() async {
          link.dispose();
          actions.dispose();
          run.dispose();
          data.dispose();
          await repository.dispose();
        });
        await pumpEventQueue();
        run.choose(mode: mode);
        await pumpEventQueue();
        link.start();
        for (var i = 0; i < 50 && !link.isRunning; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(link.isRunning, isTrue);

        link
          ..reload()
          ..restart()
          ..runCommand('reload')
          ..runCommand('restart');
        for (final status in <SessionStatus>[SessionStatus.running, SessionStatus.idle]) {
          data.publishChatHandle(
            ChatHandle(
              sessionId: 7,
              view: ChatView(sessionId: 7, agentId: 'claude', items: const [], status: status),
              insertDraft: (_) {},
            ),
          );
        }
        await pumpEventQueue();

        expect(link.canReload, isFalse);
        expect(link.mentions!.canReload, isFalse);
        expect(link.mentions!.isRunning, isTrue);
        expect((repository.reloadCalls, repository.restartCalls), (0, 0));
      });
    }
  });

  group('the @error offer', () {
    test('names the file and the line', () async {
      expect(
        await errorMention(const RunError(title: 'Boom', message: 'm', file: 'a.dart', line: 7)),
        '@error Boom (a.dart:7)',
      );
    });

    test('a file without a line is only the file, never "file:null"', () async {
      expect(
        await errorMention(const RunError(title: 'Boom', message: 'm', file: 'a.dart')),
        '@error Boom (a.dart)',
      );
    });

    test('prefers the location the app printed', () async {
      expect(
        await errorMention(
          const RunError(title: 'Boom', message: 'm', location: 'a.dart:7:3', file: 'b.dart'),
        ),
        '@error Boom (a.dart:7:3)',
      );
    });

    test('without a place there are no parentheses', () async {
      expect(await errorMention(const RunError(title: 'Boom', message: 'm')), '@error Boom');
    });
  });

  group('RunError.place', () {
    test('is the location, else file:line, else the file, else nothing', () {
      expect(
        const RunError(
          title: 't',
          message: 'm',
          location: 'x.dart:1:2',
          file: 'y.dart',
          line: 3,
        ).place,
        'x.dart:1:2',
      );
      expect(const RunError(title: 't', message: 'm', file: 'y.dart', line: 3).place, 'y.dart:3');
      expect(const RunError(title: 't', message: 'm', file: 'y.dart').place, 'y.dart');
      expect(const RunError(title: 't', message: 'm', line: 3).place, isNull);
      expect(const RunError(title: 't', message: 'm').place, isNull);
    });
  });

  group('the offer is marked Preview when the run is made up', () {
    const error = RunError(title: 'Boom', message: 'm');
    test('mentions carry the flag of the link', () async {
      Future<bool?> flag({required bool preview}) async {
        final repository = _ScriptedRun(<LogEntry>[
          LogEntry(
            seq: 0,
            time: DateTime(2026, 10, 30),
            level: LogLevel.error,
            text: 'Boom',
            error: error,
          ),
        ]);
        final data = WorkspaceDataController()..selectProject(1);
        final run = RunController(
          repository: repository,
          configRepository: MemoryRunConfigRepository(),
        )..watch(1);
        final actions = RunActionsController(
          runRepository: repository,
          pickerRepository: ScriptedWidgetPickerRepository(),
        );
        final link = WorkspaceRunLink(
          data: data,
          run: run,
          actions: actions,
          reloadAfterTurn: () => false,
          isPreview: preview,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final result = link.mentions?.isPreview;
        link.dispose();
        actions.dispose();
        run.dispose();
        data.dispose();
        return result;
      }

      expect(await flag(preview: true), isTrue);
      expect(await flag(preview: false), isFalse);
    });
  });
}
