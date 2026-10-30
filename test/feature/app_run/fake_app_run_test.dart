import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _step = Duration(milliseconds: 1);

void main() {
  late FakeAppRunRepositoryImpl repository;

  setUp(() => repository = FakeAppRunRepositoryImpl(step: _step));
  tearDown(() => repository.dispose());

  Future<void> start([int project = 1]) =>
      repository.start(project, deviceId: 'macos', mode: BuildMode.debug, target: 'lib/main.dart');

  /// Collects everything a stream emits until the test ends.
  List<T> collect<T>(Stream<T> stream) {
    final items = <T>[];
    final subscription = stream.listen(items.add);
    addTearDown(subscription.cancel);
    return items;
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 2000 && !condition(); i++) {
      await Future<void>.delayed(_step);
    }
    expect(condition(), isTrue, reason: 'condition was not met in time');
  }

  group('FakeAppRunRepositoryImpl', () {
    test('is a preview', () => expect(repository.isPreview, isTrue));

    test('start builds, then runs, then reload reports an overflow', () async {
      final states = collect(repository.watchRun(1));
      final logs = collect(repository.logs(1));

      await start();
      await until(() => states.any((state) => state is RunRunning));

      expect(states.map((state) => state.runtimeType), <Type>[
        RunIdle,
        RunBuilding,
        RunBuilding,
        RunBuilding,
        RunRunning,
      ]);
      final building = states.whereType<RunBuilding>().toList();
      expect(building.map((state) => state.progress), <double>[0.2, 0.6, 1]);
      expect(building.first.label, 'Resolving dependencies');
      expect(building[1].label, 'Xcode build');
      final running = states.last as RunRunning;
      expect(running.device.id, 'macos');
      expect(running.lastReload, isNull);
      expect(logs.last.text, 'flutter: Booking loaded 12 rooms');

      final took = await repository.hotReload(1);
      await pumpEventQueue();

      expect(took, const Duration(milliseconds: 180));
      expect((states.last as RunRunning).lastReload, took);
      expect(logs.map((log) => log.text), contains('Reloaded 3 of 812 libraries in 180ms.'));
      await until(() => logs.any((log) => log.level == LogLevel.error));
      final error = logs.last.error!;
      expect(logs.last.level, LogLevel.error);
      expect(logs.last.text, 'A RenderFlex overflowed by 24 pixels on the right.');
      expect(error.location, 'booking_card.dart:42:12');
      expect(error.file, 'lib/src/feature/booking/widgets/booking_card.dart');
      expect(error.line, 42);
      expect(error.stack, isNotEmpty);
      expect(logs.map((log) => log.seq), orderedEquals(List<int>.generate(logs.length, (i) => i)));
    });

    test('only the first reload overflows', () async {
      final logs = collect(repository.logs(1));
      await start();
      await until(() => logs.any((log) => log.text.startsWith('flutter: Booking')));
      await repository.hotReload(1);
      await until(() => logs.any((log) => log.level == LogLevel.error));
      await repository.hotReload(1);
      await Future<void>.delayed(_step * 20);

      expect(logs.where((log) => log.level == LogLevel.error), hasLength(1));
    });

    test('stop ends the run', () async {
      final states = collect(repository.watchRun(1));
      await start();
      await until(() => states.last is RunRunning);

      await repository.stop(1);
      await pumpEventQueue();

      expect(states.last, isA<RunStopped>());
    });

    test('stop during the build cancels the rest of the build', () async {
      final states = collect(repository.watchRun(1));
      await start();
      await repository.stop(1);
      await Future<void>.delayed(_step * 20);

      expect(states.last, isA<RunStopped>());
      expect(states.whereType<RunRunning>(), isEmpty);
    });

    test('a new logs listener gets the buffered lines first, with their sent flags', () async {
      final states = collect(repository.watchRun(1));
      await start();
      await until(() => states.last is RunRunning);
      await repository.markSent(1, 0);

      final replayed = await repository.logs(1).take(2).toList();

      expect(replayed.map((log) => log.seq), <int>[0, 1]);
      expect(replayed.map((log) => log.sentToAgent), <bool>[true, false]);
      expect(await repository.logs(2).take(0).toList(), isEmpty);
    });

    test('the log buffer never holds more than $kRunLogLimit lines', () async {
      final quick = FakeAppRunRepositoryImpl(step: Duration.zero);
      addTearDown(quick.dispose);
      final states = collect(quick.watchRun(1));
      await quick.start(1, deviceId: 'macos', mode: BuildMode.debug, target: 'lib/main.dart');
      await until(() => states.last is RunRunning);
      for (var i = 0; i < kRunLogLimit + 100; i++) {
        await quick.hotReload(1);
      }
      await pumpEventQueue();

      final replayed = <LogEntry>[];
      final subscription = quick.logs(1).listen(replayed.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      expect(replayed, hasLength(kRunLogLimit));
      expect(replayed.first.seq, greaterThan(0));
      expect(replayed.last.seq, replayed.first.seq + kRunLogLimit - 1);
    });

    test('reload, restart and stop without a run do nothing', () async {
      final states = collect(repository.watchRun(1));
      final logs = collect(repository.logs(1));

      expect(await repository.hotReload(1), Duration.zero);
      await repository.hotRestart(1);
      await repository.stop(1);
      await Future<void>.delayed(_step * 5);

      expect(states.single, isA<RunIdle>());
      expect(logs, isEmpty);
    });

    test('a late listener sees the current state first', () async {
      final states = collect(repository.watchRun(1));
      await start();
      await until(() => states.last is RunRunning);

      final late = await repository.watchRun(1).first;

      expect(late, isA<RunRunning>());
    });

    test('projects run independently', () async {
      final first = collect(repository.watchRun(1));
      final second = collect(repository.watchRun(2));

      await start();
      await until(() => first.last is RunRunning);

      expect(second.single, isA<RunIdle>());
    });

    test('starting a running project restarts it', () async {
      final states = collect(repository.watchRun(1));
      await start();
      await until(() => states.last is RunRunning);

      await start();
      await until(() => states.last is RunRunning && states.whereType<RunStopped>().isNotEmpty);

      expect(states.whereType<RunStopped>(), hasLength(1));
      expect(states.whereType<RunRunning>(), hasLength(2));
    });

    test('hot restart reports its time', () async {
      final states = collect(repository.watchRun(1));
      await start();
      await until(() => states.last is RunRunning);

      await repository.hotRestart(1);
      await pumpEventQueue();

      expect((states.last as RunRunning).lastReload, const Duration(milliseconds: 640));
    });

    test('dispose closes every stream and stops the scenario', () async {
      final done = Completer<void>();
      final logsDone = Completer<void>();
      repository.watchRun(1).listen((_) {}, onDone: done.complete);
      repository.logs(1).listen((_) {}, onDone: logsDone.complete);
      await start();

      await repository.dispose();

      await done.future;
      await logsDone.future;
      expect(await repository.watchRun(1).toList(), isEmpty);
    });

    test('cancelling a subscription closes nothing else', () async {
      final first = repository.watchRun(1).listen((_) {});
      final second = collect(repository.watchRun(1));
      await first.cancel();

      await start();
      await until(() => second.last is RunRunning);
    });
  });

  group('RunError.forAgent', () {
    test('the agent text of an error has the place and a stack excerpt', () {
      final stack = List<String>.generate(30, (i) => '#$i frame $i').join('\n');
      final error = RunError(
        title: 'Overflow',
        message: 'A RenderFlex overflowed by 24 pixels on the right.',
        location: 'booking_card.dart:42:12',
        stack: stack,
      );

      final text = error.forAgent();

      expect(text, contains('Overflow'));
      expect(text, contains('A RenderFlex overflowed by 24 pixels on the right.'));
      expect(text, contains('booking_card.dart:42:12'));
      expect(text, contains('```'));
      expect(text, contains('#19 frame 19'));
      expect(text, isNot(contains('#20 frame 20')));
    });

    test('an error without a place or a stack is only the title and the message', () {
      const error = RunError(title: 'Boom', message: 'It broke');

      expect(error.forAgent(), isNot(contains('```')));
      expect(error.forAgent(), contains('It broke'));
    });
  });

  group('FakeDevicesRepositoryImpl', () {
    test('lists running and available devices', () async {
      final devices = FakeDevicesRepositoryImpl(step: _step);

      final list = await devices.watchDevices().first;

      expect(devices.isPreview, isTrue);
      expect(
        list.where((device) => device.kind == DeviceKind.running).map((device) => device.name),
        <String>['iPhone 16 Pro', 'macOS', 'Chrome'],
      );
      expect(
        list.where((device) => device.kind == DeviceKind.available).map((device) => device.name),
        <String>['Pixel 9 API 35', 'iPad Air (M3)'],
      );
      expect(list.first.platform, DevicePlatform.ios);
    });

    test('the stream closes when the listener cancels', () async {
      final devices = FakeDevicesRepositoryImpl(step: _step);
      final subscription = devices.watchDevices().listen((_) {});

      await subscription.cancel();
    });
  });

  group('FakeWidgetPickerRepositoryImpl', () {
    test('picks the booking card', () async {
      final picker = FakeWidgetPickerRepositoryImpl(step: _step);

      final picked = await picker.pick(1);

      expect(picker.isPreview, isTrue);
      expect(picked!.name, 'BookingCard');
      expect(picked.file, 'lib/src/feature/booking/widgets/booking_card.dart');
      expect(picked.line, 42);
      expect(picked.ancestors, <String>[
        'Row',
        'Padding',
        'BookingCard',
        'ListView',
        'BookingScreen',
      ]);
    });
  });
}
