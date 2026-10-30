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

/// Made-up devices until the Flutter tooling is wired in.
final class FakeDevicesRepositoryImpl implements IDevicesRepository {
  /// Creates the repository; [step] is the time "detecting" the devices takes.
  FakeDevicesRepositoryImpl({this.step = const Duration(milliseconds: 400)});

  /// The time one operation takes.
  final Duration step;

  @override
  bool get isPreview => true;

  @override
  Stream<List<Device>> watchDevices() {
    final controller = StreamController<List<Device>>();
    Timer? timer;
    controller
      ..onListen = () {
        timer = Timer(step, () {
          if (!controller.isClosed) controller.add(kFakeDevices);
        });
      }
      ..onCancel = () async {
        timer?.cancel();
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }
}
