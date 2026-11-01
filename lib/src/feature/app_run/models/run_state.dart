import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/build_mode.dart';
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
  const RunBuilding({this.progress, this.label});

  /// How far the build is, from 0 to 1; `null` when it is not known.
  final double? progress;

  /// What it is doing now, for example `Building macOS application...`; `null` when it is not known.
  final String? label;

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
  const RunRunning({
    required this.device,
    required this.startedAt,
    this.mode = BuildMode.debug,
    this.vmServiceUri,
    this.dtdUri,
    this.devToolsUri,
    this.lastReload,
  });

  /// The device the app runs on.
  final Device device;

  /// When the app came up.
  final DateTime startedAt;

  /// The build mode the app was built in.
  final BuildMode mode;

  /// The VM service of the app (`ws://…`); `null` until `flutter run` reports it, and in release.
  final Uri? vmServiceUri;

  /// The Dart Tooling Daemon `flutter run` serves for the app; `null` when there is none.
  final Uri? dtdUri;

  /// DevTools connected to the app; `null` when it is not served.
  final Uri? devToolsUri;

  /// How long the last hot reload or restart took; `null` before the first one.
  final Duration? lastReload;

  /// A copy with the given reload time.
  RunRunning withReload(Duration lastReload) => copyWith(lastReload: lastReload);

  /// A copy with the given fields replaced.
  RunRunning copyWith({Uri? vmServiceUri, Uri? dtdUri, Uri? devToolsUri, Duration? lastReload}) =>
      RunRunning(
        device: device,
        startedAt: startedAt,
        mode: mode,
        vmServiceUri: vmServiceUri ?? this.vmServiceUri,
        dtdUri: dtdUri ?? this.dtdUri,
        devToolsUri: devToolsUri ?? this.devToolsUri,
        lastReload: lastReload ?? this.lastReload,
      );

  @override
  bool operator ==(Object other) =>
      other is RunRunning &&
      other.device == device &&
      other.startedAt == startedAt &&
      other.mode == mode &&
      other.vmServiceUri == vmServiceUri &&
      other.dtdUri == dtdUri &&
      other.devToolsUri == devToolsUri &&
      other.lastReload == lastReload;

  @override
  int get hashCode => Object.hash(
    RunRunning,
    device,
    startedAt,
    mode,
    vmServiceUri,
    dtdUri,
    devToolsUri,
    lastReload,
  );

  @override
  String toString() => 'RunRunning(${device.name}, ${mode.name}, $lastReload)';
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
