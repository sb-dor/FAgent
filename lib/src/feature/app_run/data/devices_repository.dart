import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';

/// The devices `flutter run` can target.
abstract interface class IDevicesRepository {
  /// Whether the data is made up (the repository is a stand-in until the real one lands).
  bool get isPreview;

  /// The current device list, then every change. Ends when the subscription is cancelled.
  Stream<List<Device>> watchDevices();
}
