import 'package:flutter/foundation.dart';

/// The platform a [Device] runs Flutter on.
enum DevicePlatform { ios, android, macos, web, windows, linux }

/// Whether a [Device] is already up or can be launched.
enum DeviceKind {
  /// A booted simulator, a connected phone, the desktop itself.
  running,

  /// An emulator or simulator that is installed but not booted.
  available,
}

/// A target `flutter run` can start the app on.
@immutable
final class Device {
  /// Creates a device.
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.kind,
    this.detail,
  });

  /// The id `flutter run -d` takes.
  final String id;

  /// What the user sees, for example `iPhone 16 Pro`.
  final String name;

  /// The platform of the device.
  final DevicePlatform platform;

  /// Whether the device is running or only available.
  final DeviceKind kind;

  /// A short note under the name, for example `Simulator`; `null` when there is none.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device &&
          other.id == id &&
          other.name == name &&
          other.platform == platform &&
          other.kind == kind &&
          other.detail == detail;

  @override
  int get hashCode => Object.hash(id, name, platform, kind, detail);

  @override
  String toString() => 'Device($id, $name, ${platform.name}, ${kind.name})';
}
