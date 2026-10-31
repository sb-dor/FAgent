import 'dart:async';

import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_daemon_process.dart';

const Map<String, Object?> _macos = <String, Object?>{
  'id': 'macos',
  'name': 'macOS',
  'platformType': 'macos',
  'emulator': false,
  'sdk': 'macOS 26.0',
};

const Map<String, Object?> _runningPixel = <String, Object?>{
  'id': 'emulator-5554',
  'name': 'sdk gphone64',
  'platformType': 'android',
  'emulator': true,
  'emulatorId': 'Pixel_9_API_35',
  'sdk': 'Android 15',
};

const Map<String, Object?> _pixel9 = <String, Object?>{
  'id': 'Pixel_9_API_35',
  'name': 'Pixel 9 API 35',
  'platformType': 'android',
};

const Map<String, Object?> _tablet = <String, Object?>{
  'id': 'Pixel_Tablet',
  'name': 'Pixel Tablet',
  'platformType': 'android',
};

void main() {
  group('DevicesRepositoryImpl', () {
    late List<ScriptedDaemonProcess> started;
    late List<Object?> devicesAnswer;
    late List<Object?> emulatorsAnswer;
    late Set<String> silentMethods;
    late String? flutterPath;
    late DevicesRepositoryImpl repository;
    late List<List<Device>> lists;
    late List<Object> errors;
    late bool done;
    final subscriptions = <StreamSubscription<List<Device>>>[];

    ScriptedDaemonProcess create() {
      final process = ScriptedDaemonProcess();
      process.onRequest = (request) {
        final method = request['method']! as String;
        if (silentMethods.contains(method)) return;
        final id = request['id']! as int;
        process.respond(
          id,
          result: switch (method) {
            'device.getDevices' => devicesAnswer,
            'emulator.getEmulators' => emulatorsAnswer,
            _ => null,
          },
        );
      };
      return process;
    }

    List<String> methods(ScriptedDaemonProcess process) =>
        process.sent.map((request) => request['method']! as String).toList();

    StreamSubscription<List<Device>> watch() {
      final subscription = repository.watchDevices().listen(
        lists.add,
        onError: errors.add,
        onDone: () => done = true,
      );
      subscriptions.add(subscription);
      return subscription;
    }

    Future<void> connect([int index = 0]) async {
      await pumpEventQueue();
      started[index].emit(<String, Object?>{
        'event': 'daemon.connected',
        'params': <String, Object?>{},
      });
      await pumpEventQueue();
    }

    setUp(() {
      started = <ScriptedDaemonProcess>[];
      devicesAnswer = <Object?>[_macos, _runningPixel];
      emulatorsAnswer = <Object?>[_pixel9, _tablet];
      silentMethods = <String>{};
      flutterPath = '/opt/flutter/bin/flutter';
      lists = <List<Device>>[];
      errors = <Object>[];
      done = false;
      repository = DevicesRepositoryImpl(
        flutter: () => flutterPath,
        environment: const <String, String>{'PATH': '/usr/bin'},
        start: scriptedStarter(create, started: started),
      );
    });

    tearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
      await repository.dispose();
    });

    test('is not a preview', () {
      expect(repository.isPreview, isFalse);
    });

    test('does nothing until someone listens', () async {
      repository.watchDevices();
      await pumpEventQueue();

      expect(started, isEmpty);
    });

    test('starts `flutter daemon` with the environment', () async {
      watch();
      await pumpEventQueue();

      expect(started, hasLength(1));
      expect(started.single.executable, '/opt/flutter/bin/flutter');
      expect(started.single.arguments, <String>['daemon']);
      expect(started.single.environment, <String, String>{'PATH': '/usr/bin'});
    });

    test('asks for the devices only once the daemon is connected', () async {
      watch();
      await pumpEventQueue();
      expect(started.single.sent, isEmpty);

      await connect();

      expect(methods(started.single), <String>[
        'device.enable',
        'device.getDevices',
        'emulator.getEmulators',
      ]);
    });

    test('the first list comes after both answers', () async {
      silentMethods.add('emulator.getEmulators');
      watch();
      await connect();
      expect(lists, isEmpty);

      final request = started.single.sent.last;
      expect(request['method'], 'emulator.getEmulators');
      started.single.respond(request['id']! as int, result: emulatorsAnswer);
      await pumpEventQueue();

      expect(lists, hasLength(1));
    });

    test('running devices come first, then the emulators that are not running', () async {
      watch();
      await connect();

      expect(lists.single, const <Device>[
        Device(
          id: 'macos',
          name: 'macOS',
          platform: DevicePlatform.macos,
          kind: DeviceKind.running,
          detail: 'macOS 26.0',
        ),
        Device(
          id: 'emulator-5554',
          name: 'sdk gphone64',
          platform: DevicePlatform.android,
          kind: DeviceKind.running,
          detail: 'Android 15',
          emulatorId: 'Pixel_9_API_35',
        ),
        Device(
          id: 'emulator:Pixel_Tablet',
          name: 'Pixel Tablet',
          platform: DevicePlatform.android,
          kind: DeviceKind.available,
          emulatorId: 'Pixel_Tablet',
        ),
      ]);
    });

    test('platforms the app cannot show are skipped', () async {
      devicesAnswer = <Object?>[
        _macos,
        <String, Object?>{'id': 'fuchsia', 'name': 'Fuchsia', 'platformType': 'fuchsia'},
      ];
      emulatorsAnswer = <Object?>[
        <String, Object?>{'id': 'F', 'name': 'Fuchsia emulator', 'platformType': 'fuchsia'},
      ];
      watch();
      await connect();

      expect(lists.single.map((device) => device.id), <String>['macos']);
    });

    test('the platforms map one to one', () async {
      devicesAnswer = <Object?>[
        for (final platform in const <String>['ios', 'android', 'macos', 'web', 'windows', 'linux'])
          <String, Object?>{'id': platform, 'name': platform, 'platformType': platform},
      ];
      emulatorsAnswer = <Object?>[];
      watch();
      await connect();

      expect(lists.single.map((device) => device.platform), DevicePlatform.values);
    });

    test('a removed device leaves the list and its emulator becomes available', () async {
      watch();
      await connect();

      started.single.emit(<String, Object?>{'event': 'device.removed', 'params': _runningPixel});
      await pumpEventQueue();

      expect(lists.last.map((device) => device.id), <String>[
        'macos',
        'emulator:Pixel_9_API_35',
        'emulator:Pixel_Tablet',
      ]);
      expect(lists.last[1].kind, DeviceKind.available);
      expect(
        methods(started.single).where((method) => method == 'emulator.getEmulators'),
        hasLength(2),
        reason: 'the emulators are asked for again',
      );
    });

    test('an added device joins the list and its emulator is no longer available', () async {
      devicesAnswer = <Object?>[_macos];
      watch();
      await connect();
      expect(lists.single.map((device) => device.id), <String>[
        'macos',
        'emulator:Pixel_9_API_35',
        'emulator:Pixel_Tablet',
      ]);

      started.single.emit(<String, Object?>{'event': 'device.added', 'params': _runningPixel});
      await pumpEventQueue();

      expect(lists.last.map((device) => device.id), <String>[
        'macos',
        'emulator-5554',
        'emulator:Pixel_Tablet',
      ]);
    });

    test('an added device that is already known replaces the old entry', () async {
      watch();
      await connect();

      started.single.emit(<String, Object?>{
        'event': 'device.added',
        'params': <String, Object?>{..._macos, 'name': 'My Mac'},
      });
      await pumpEventQueue();

      expect(lists.last.where((device) => device.id == 'macos').single.name, 'My Mac');
    });

    test('launch asks the daemon to start the emulator without a cold boot', () async {
      watch();
      await connect();

      await repository.launch('emulator:Pixel_Tablet');

      final request = started.single.sent.last;
      expect(request['method'], 'emulator.launch');
      expect(request['params'], <String, Object?>{'emulatorId': 'Pixel_Tablet', 'coldBoot': false});
    });

    test('launch of a device that is not an emulator does nothing', () async {
      watch();
      await connect();
      final before = started.single.sent.length;

      await repository.launch('macos');

      expect(started.single.sent, hasLength(before));
    });

    test('launch fails when the daemon rejects it', () async {
      watch();
      await connect();
      silentMethods.add('emulator.launch');
      final result = repository.launch('emulator:Pixel_Tablet');
      await pumpEventQueue();
      started.single.respond(started.single.sent.last['id']! as int, error: 'no such emulator');

      await expectLater(result, throwsA(isA<Object>()));
    });

    test('a missing Flutter SDK ends the stream with FlutterNotFoundException', () async {
      flutterPath = null;
      watch();
      await pumpEventQueue();

      expect(errors.single, isA<FlutterNotFoundException>());
      expect(done, isTrue);
      expect(started, isEmpty);
    });

    test('the daemon stops when the last listener leaves', () async {
      final first = watch();
      await connect();
      final second = watch();
      await pumpEventQueue();
      expect(started, hasLength(1), reason: 'one daemon for every listener');
      expect(lists, hasLength(2), reason: 'a late listener gets the current list');

      await first.cancel();
      expect(started.single.stopped, isFalse);

      await second.cancel();
      expect(started.single.stopped, isTrue);
    });

    test('a new listener after the last left starts a new daemon', () async {
      final first = watch();
      await connect();
      await first.cancel();

      watch();
      await connect(1);

      expect(started, hasLength(2));
      expect(lists, hasLength(2));
    });

    test('the daemon dying ends the stream with DaemonClosedException', () async {
      watch();
      await connect();

      started.single.exit(1);
      await pumpEventQueue();

      expect(errors.single, isA<DaemonClosedException>());
      expect(done, isTrue);
    });

    test('the daemon dying before it connects ends the stream the same way', () async {
      watch();
      await pumpEventQueue();

      started.single.exit(1);
      await pumpEventQueue();

      expect(errors.single, isA<DaemonClosedException>());
      expect(done, isTrue);
    });

    test('the next watch after the daemon died starts a new daemon', () async {
      watch();
      await connect();
      started.single.exit(1);
      await pumpEventQueue();

      watch();
      await connect(1);

      expect(started, hasLength(2));
      expect(lists, hasLength(2));
      expect(started[1].stopped, isFalse);
    });

    test('a rejected getDevices ends the stream with the error and stops the daemon', () async {
      silentMethods.add('device.getDevices');
      watch();
      await connect();
      final request = started.single.sent.firstWhere(
        (request) => request['method'] == 'device.getDevices',
      );
      started.single.respond(request['id']! as int, error: 'boom');
      await pumpEventQueue();

      expect(errors.single, isA<Object>());
      expect(lists, isEmpty);
      expect(done, isTrue);
      expect(started.single.stopped, isTrue);
    });

    test('dispose stops the daemon and closes the streams', () async {
      watch();
      await connect();

      await repository.dispose();
      await pumpEventQueue();

      expect(started.single.stopped, isTrue);
      expect(done, isTrue);
      expect(errors, isEmpty);
    });

    test('disposing twice is harmless: quitting disposes, then the app disposes again', () async {
      watch();
      await connect();

      await repository.dispose();
      await repository.dispose();

      expect(started, hasLength(1));
      expect(started.single.stopped, isTrue);
      expect(repository.watchDevices(), emitsDone);
    });
  });
}
