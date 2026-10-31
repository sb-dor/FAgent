import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_test/flutter_test.dart';

const _step = Duration(milliseconds: 1);

void main() {
  group('DevicesController', () {
    late FakeDevicesRepositoryImpl repository;
    late DevicesController controller;

    setUp(() => repository = FakeDevicesRepositoryImpl(step: _step));

    tearDown(() async {
      controller.dispose();
      await repository.dispose();
    });

    test('launch asks the repository to boot the device', () async {
      controller = DevicesController(repository: repository)..watch();
      await Future<void>.delayed(_step * 50);

      controller.launch('android-pixel-9');
      await pumpEventQueue();

      expect(repository.launched, <String>['android-pixel-9']);
    });

    test('launch keeps the device list', () async {
      controller = DevicesController(repository: repository)..watch();
      await Future<void>.delayed(_step * 50);
      final before = controller.state;

      controller.launch('android-pixel-9');
      await pumpEventQueue();

      expect(controller.state, before);
    });

    test('a launch that fails does not turn the list into an error', () async {
      final failing = _ScriptedRepository()..launchError = Exception('no emulator');
      controller = DevicesController(repository: failing)..watch();
      await pumpEventQueue();
      failing.emit(const <Device>[]);
      await pumpEventQueue();

      controller.launch('android-pixel-9');
      await pumpEventQueue();

      expect(controller.state, isA<Devices$CompletedState>());
      await failing.dispose();
    });

    test('the list follows the repository', () async {
      controller = DevicesController(repository: repository)..watch();
      await Future<void>.delayed(_step * 50);

      repository.set(const <Device>[
        Device(
          id: 'macos',
          name: 'macOS',
          platform: DevicePlatform.macos,
          kind: DeviceKind.running,
        ),
      ]);
      await pumpEventQueue();

      final state = controller.state as Devices$CompletedState;
      expect(state.devices.single.id, 'macos');
    });

    test('an error of the stream becomes the error state; watch starts over', () async {
      final scripted = _ScriptedRepository();
      controller = DevicesController(repository: scripted)..watch();
      await pumpEventQueue();
      scripted.fail(StateError('boom'));
      await pumpEventQueue();
      expect(controller.state, isA<Devices$ErrorState>());

      controller.watch();
      await pumpEventQueue();
      expect(scripted.watches, 2);
      expect(controller.state, isA<Devices$InProgressState>());
      await scripted.dispose();
    });
  });
}

final class _ScriptedRepository implements IDevicesRepository {
  int watches = 0;
  StreamController<List<Device>>? _controller;

  Exception? launchError;

  void fail(Object error) => _controller!.addError(error);

  void emit(List<Device> devices) => _controller!.add(devices);

  @override
  bool get isPreview => false;

  @override
  Stream<List<Device>> watchDevices() {
    watches++;
    return (_controller = StreamController<List<Device>>()).stream;
  }

  @override
  Future<void> launch(String deviceId) async {
    if (launchError case final error?) throw error;
  }

  @override
  Future<void> dispose() async => _controller?.close();
}
