import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

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
    _subscription = _repository.watchDevices().listen(
      (devices) => setState(DevicesState.completed(devices)),
      onError: (Object error) => setState(DevicesState.error(error: error)),
    );
  }, error: (error, stackTrace) async => setState(DevicesState.error(error: error)));

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
