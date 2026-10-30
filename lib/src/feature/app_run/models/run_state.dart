import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';

/// Where a project's app is in its run.
@immutable
sealed class RunState {
  const RunState();
}

/// Nothing was started yet.
final class RunIdle extends RunState {
  /// Creates the state.
  const RunIdle();

  @override
  bool operator ==(Object other) => other is RunIdle;

  @override
  int get hashCode => (RunIdle).hashCode;

  @override
  String toString() => 'RunIdle';
}

/// `flutter run` is compiling and installing the app.
final class RunBuilding extends RunState {
  /// Creates the state.
  const RunBuilding({required this.progress, required this.label});

  /// How far the build is, from 0 to 1.
  final double progress;

  /// What it is doing now, for example `Xcode build`.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is RunBuilding && other.progress == progress && other.label == label;

  @override
  int get hashCode => Object.hash(RunBuilding, progress, label);

  @override
  String toString() => 'RunBuilding($progress, $label)';
}

/// The app is up on [device].
final class RunRunning extends RunState {
  /// Creates the state.
  const RunRunning({required this.device, required this.startedAt, this.lastReload});

  /// The device the app runs on.
  final Device device;

  /// When the app came up.
  final DateTime startedAt;

  /// How long the last hot reload or restart took; `null` before the first one.
  final Duration? lastReload;

  /// A copy with the given reload time.
  RunRunning withReload(Duration lastReload) =>
      RunRunning(device: device, startedAt: startedAt, lastReload: lastReload);

  @override
  bool operator ==(Object other) =>
      other is RunRunning &&
      other.device == device &&
      other.startedAt == startedAt &&
      other.lastReload == lastReload;

  @override
  int get hashCode => Object.hash(RunRunning, device, startedAt, lastReload);

  @override
  String toString() => 'RunRunning(${device.name}, $lastReload)';
}

/// The app could not be started or died.
final class RunFailed extends RunState {
  /// Creates the state.
  const RunFailed({required this.error});

  /// What went wrong.
  final RunError error;

  @override
  bool operator ==(Object other) => other is RunFailed && other.error == error;

  @override
  int get hashCode => Object.hash(RunFailed, error);

  @override
  String toString() => 'RunFailed($error)';
}

/// The user stopped the app.
final class RunStopped extends RunState {
  /// Creates the state.
  const RunStopped();

  @override
  bool operator ==(Object other) => other is RunStopped;

  @override
  int get hashCode => (RunStopped).hashCode;

  @override
  String toString() => 'RunStopped';
}
