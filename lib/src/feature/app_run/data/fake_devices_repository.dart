import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';

/// The devices the fake repositories know. Deterministic.
const List<Device> kFakeDevices = <Device>[
  Device(
    id: 'ios-sim-16-pro',
    name: 'iPhone 16 Pro',
    platform: DevicePlatform.ios,
    kind: DeviceKind.running,
    detail: 'Simulator',
  ),
  Device(id: 'macos', name: 'macOS', platform: DevicePlatform.macos, kind: DeviceKind.running),
  Device(id: 'chrome', name: 'Chrome', platform: DevicePlatform.web, kind: DeviceKind.running),
  Device(
    id: 'android-pixel-9',
    name: 'Pixel 9 API 35',
    platform: DevicePlatform.android,
    kind: DeviceKind.available,
    detail: 'Emulator',
  ),
  Device(
    id: 'ios-sim-ipad-air',
    name: 'iPad Air (M3)',
    platform: DevicePlatform.ios,
    kind: DeviceKind.available,
    detail: 'Simulator',
  ),
];

/// Made-up devices until the Flutter tooling is wired in. A test can replace the list with [set]
/// and read the emulators it asked to boot from [launched].
final class FakeDevicesRepositoryImpl implements IDevicesRepository {
  /// Creates the repository; [step] is the time "detecting" the devices takes.
  FakeDevicesRepositoryImpl({this.step = const Duration(milliseconds: 400)});

  /// The time one operation takes.
  final Duration step;

  /// The ids passed to [launch] that belong to an available device, in order.
  final List<String> launched = <String>[];

  final List<StreamController<List<Device>>> _controllers = <StreamController<List<Device>>>[];
  List<Device> _devices = kFakeDevices;

  @override
  bool get isPreview => true;

  /// Replaces the device list: every listener gets [devices] now, and a listener that comes later
  /// gets them as its first list.
  void set(List<Device> devices) {
    _devices = devices;
    for (final controller in List<StreamController<List<Device>>>.of(_controllers)) {
      if (!controller.isClosed) controller.add(devices);
    }
  }

  @override
  Stream<List<Device>> watchDevices() {
    final controller = StreamController<List<Device>>();
    Timer? timer;
    controller
      ..onListen = () {
        _controllers.add(controller);
        timer = Timer(step, () {
          if (!controller.isClosed) controller.add(_devices);
        });
      }
      ..onCancel = () async {
        timer?.cancel();
        _controllers.remove(controller);
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> launch(String deviceId) async {
    final device = _devices.where((device) => device.id == deviceId).firstOrNull;
    if (device != null && device.kind == DeviceKind.available) launched.add(deviceId);
  }

  @override
  Future<void> dispose() async {
    final controllers = List<StreamController<List<Device>>>.of(_controllers);
    _controllers.clear();
    for (final controller in controllers) {
      if (!controller.isClosed) await controller.close();
    }
  }
}
