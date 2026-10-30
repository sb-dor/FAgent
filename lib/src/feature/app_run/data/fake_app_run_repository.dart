import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';

/// What one project's fake run holds: its state, its output and the timers of the running scenario.
final class _FakeRun {
  final StreamController<RunState> states = StreamController<RunState>.broadcast();
  final StreamController<LogEntry> logs = StreamController<LogEntry>.broadcast();
  final Map<Timer, Completer<bool>> _waits = <Timer, Completer<bool>>{};

  RunState state = const RunIdle();
  int nextSeq = 0;
  int reloads = 0;

  /// Changes with every start and stop, so a scenario that was cut off notices.
  int generation = 0;

  void setState(RunState value) {
    state = value;
    if (!states.isClosed) states.add(value);
  }

  void log(LogLevel level, String text, {RunError? error}) {
    final entry = LogEntry(
      seq: nextSeq++,
      time: DateTime.now(),
      level: level,
      text: text,
      error: error,
    );
    if (!logs.isClosed) logs.add(entry);
  }

  /// Waits [duration]; completes with `false` when the scenario was cancelled meanwhile.
  Future<bool> wait(Duration duration) {
    final completer = Completer<bool>();
    late final Timer timer;
    timer = Timer(duration, () {
      _waits.remove(timer);
      completer.complete(true);
    });
    _waits[timer] = completer;
    return completer.future;
  }

  /// Cuts off every pending wait.
  void cancel() {
    generation++;
    for (final MapEntry(:key, :value) in _waits.entries.toList()) {
      key.cancel();
      value.complete(false);
    }
    _waits.clear();
  }

  Future<void> close() async {
    cancel();
    await states.close();
    await logs.close();
  }
}

/// A made-up run: build, run, a layout overflow after the first hot reload.
///
/// Every delay is [step], so a test passes a tiny one. State is kept per project.
final class FakeAppRunRepositoryImpl implements IAppRunRepository {
  /// Creates the repository.
  FakeAppRunRepositoryImpl({this.step = const Duration(milliseconds: 600)});

  /// The time one phase of the scenario takes.
  final Duration step;

  final Map<int, _FakeRun> _runs = <int, _FakeRun>{};
  bool _disposed = false;

  @override
  bool get isPreview => true;

  _FakeRun _run(int projectId) => _runs.putIfAbsent(projectId, _FakeRun.new);

  @override
  Stream<RunState> watchRun(int projectId) => _stream<RunState>(
    projectId,
    source: (run) => run.states.stream,
    initial: (run) => <RunState>[run.state],
  );

  @override
  Stream<LogEntry> logs(int projectId) => _stream<LogEntry>(
    projectId,
    source: (run) => run.logs.stream,
    initial: (run) => const <LogEntry>[],
  );

  /// A stream that first replays [initial] and then forwards [source]; it closes on cancel.
  Stream<T> _stream<T>(
    int projectId, {
    required Stream<T> Function(_FakeRun run) source,
    required List<T> Function(_FakeRun run) initial,
  }) {
    if (_disposed) return const Stream.empty();
    final run = _run(projectId);
    final controller = StreamController<T>();
    StreamSubscription<T>? subscription;
    controller
      ..onListen = () {
        initial(run).forEach(controller.add);
        subscription = source(run).listen(
          controller.add,
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
        );
      }
      ..onCancel = () async {
        await subscription?.cancel();
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> start(
    int projectId, {
    required String deviceId,
    required BuildMode mode,
    required String target,
  }) async {
    if (_disposed) return;
    final run = _run(projectId);
    if (run.state is RunBuilding || run.state is RunRunning) await stop(projectId);
    run.reloads = 0;
    final generation = ++run.generation;
    final device = kFakeDevices.firstWhere(
      (device) => device.id == deviceId,
      orElse: () => Device(
        id: deviceId,
        name: deviceId,
        platform: DevicePlatform.macos,
        kind: DeviceKind.running,
      ),
    );
    run
      ..setState(const RunBuilding(progress: 0.2, label: 'Resolving dependencies'))
      ..log(LogLevel.info, 'Launching $target on ${device.name} in ${mode.name} mode...');
    unawaited(_build(run, generation, device));
  }

  Future<void> _build(_FakeRun run, int generation, Device device) async {
    if (!await run.wait(step) || run.generation != generation) return;
    run.setState(const RunBuilding(progress: 0.6, label: 'Xcode build'));
    if (!await run.wait(step) || run.generation != generation) return;
    run.setState(const RunBuilding(progress: 1, label: 'Starting the app'));
    if (!await run.wait(step) || run.generation != generation) return;
    run
      ..setState(RunRunning(device: device, startedAt: DateTime.now()))
      ..log(LogLevel.info, 'flutter: Booking loaded 12 rooms');
  }

  @override
  Future<void> stop(int projectId) async {
    final run = _runs[projectId];
    if (run == null || (run.state is! RunBuilding && run.state is! RunRunning)) return;
    run
      ..cancel()
      ..log(LogLevel.info, 'Application finished.')
      ..setState(const RunStopped());
  }

  @override
  Future<Duration> hotReload(int projectId) async {
    final run = _runs[projectId];
    if (run == null || run.state is! RunRunning) return Duration.zero;
    final generation = run.generation;
    if (!await run.wait(step) || run.generation != generation) return Duration.zero;
    const took = Duration(milliseconds: 180);
    final first = run.reloads++ == 0;
    run.log(
      LogLevel.info,
      first ? 'Reloaded 3 of 812 libraries in 180ms.' : 'Reloaded 1 of 812 libraries in 180ms.',
    );
    if (run.state case final RunRunning running) run.setState(running.withReload(took));
    if (first) unawaited(_overflow(run, generation));
    return took;
  }

  Future<void> _overflow(_FakeRun run, int generation) async {
    if (!await run.wait(step) || run.generation != generation) return;
    const message = 'A RenderFlex overflowed by 24 pixels on the right.';
    run.log(
      LogLevel.error,
      message,
      error: const RunError(
        title: 'Layout overflow',
        message: message,
        location: 'booking_card.dart:42:12',
        file: 'lib/src/feature/booking/widgets/booking_card.dart',
        line: 42,
        stack:
            '#0 RenderFlex.paint.<anonymous closure> (package:flutter/src/rendering/flex.dart:1163:9)\n'
            '#1 BookingCard.build (package:booking/src/feature/booking/widgets/booking_card.dart:42:12)\n'
            '#2 StatelessElement.build (package:flutter/src/widgets/framework.dart:5746:27)\n'
            '#3 ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:5674:15)',
      ),
    );
  }

  @override
  Future<void> hotRestart(int projectId) async {
    final run = _runs[projectId];
    if (run == null || run.state is! RunRunning) return;
    final generation = run.generation;
    if (!await run.wait(step) || run.generation != generation) return;
    const took = Duration(milliseconds: 640);
    run.log(LogLevel.info, 'Restarted application in 640ms.');
    if (run.state case final RunRunning running) run.setState(running.withReload(took));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final run in _runs.values) {
      await run.close();
    }
    _runs.clear();
  }
}
