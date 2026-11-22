import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:l/l.dart';

part 'devices_controller.freezed.dart';

@freezed
sealed class DevicesState with _$DevicesState {
  const factory DevicesState.initial() = Devices$InitialState;

  const factory DevicesState.inProgress() = Devices$InProgressState;

  const factory DevicesState.error({Object? error}) = Devices$ErrorState;

  const factory DevicesState.completed(List<Device> devices) = Devices$CompletedState;
}

/// Keeps the list of devices the app can run on up to date.
final class DevicesController extends StateController<DevicesState>
    with SequentialControllerHandler {
  DevicesController({required this._repository, super.initialState = const DevicesState.initial()});

  final IDevicesRepository _repository;
  StreamSubscription<List<Device>>? _subscription;

  /// Starts following the device list; the state is `inProgress` until the first list arrives.
  void watch() => handle(() async {
    setState(const DevicesState.inProgress());
    await _subscription?.cancel();
    _subscription = _repository.watchDevices().listen((devices) {
      _pruneLaunches(devices);
      setState(DevicesState.completed(devices));
    }, onError: (Object error) => setState(DevicesState.error(error: error)));
  }, error: (error, stackTrace) async => setState(DevicesState.error(error: error)));

  /// The ids of the devices being booted: asked for, and still in the list as available.
  final Set<String> _launching = <String>{};

  /// The ids whose last launch failed.
  final Set<String> _failedLaunches = <String>{};

  /// Whether the launch of [deviceId] was asked for and the device has not shown up yet.
  bool isLaunching(String deviceId) => _launching.contains(deviceId);

  /// Whether the last launch of [deviceId] failed; launching it again clears that.
  bool launchFailed(String deviceId) => _failedLaunches.contains(deviceId);

  /// Boots the emulator behind [deviceId]; the booted device arrives through [watch]. A device
  /// that is not in the list as available is left alone, and so is one that is already being
  /// booted (asking again changes nothing, unless the last try failed).
  ///
  /// Not queued behind [watch]: booting an emulator takes a while. A failure is logged and
  /// remembered ([launchFailed]); the device list stays as it is.
  void launch(String deviceId) {
    final known = switch (state) {
      Devices$CompletedState(:final devices) =>
        devices.where((device) => device.id == deviceId).firstOrNull,
      _ => null,
    };
    if (known == null || known.kind != DeviceKind.available || _launching.contains(deviceId)) {
      return;
    }
    _failedLaunches.remove(deviceId);
    _launching.add(deviceId);
    notifyListeners();
    _repository.launch(deviceId).catchError((Object error, StackTrace stackTrace) {
      l.w('DevicesController | cannot launch $deviceId: $error');
      _launching.remove(deviceId);
      _failedLaunches.add(deviceId);
      if (!isDisposed) notifyListeners();
    }).ignore();
  }

  /// Forgets the launches of devices that are no longer available: they have booted (or left).
  void _pruneLaunches(List<Device> devices) {
    final available = <String>{
      for (final device in devices)
        if (device.kind == DeviceKind.available) device.id,
    };
    _launching.removeWhere((id) => !available.contains(id));
    _failedLaunches.removeWhere((id) => !available.contains(id));
  }

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
