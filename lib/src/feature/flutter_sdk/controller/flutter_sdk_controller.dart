import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'flutter_sdk_controller.freezed.dart';

@freezed
sealed class FlutterSdkState with _$FlutterSdkState {
  /// Nothing was loaded yet.
  const factory FlutterSdkState.initial() = FlutterSdk$InitialState;

  /// The first load is running.
  const factory FlutterSdkState.inProgress() = FlutterSdk$InProgressState;

  /// The [sdk] is known. [checks] is the last `flutter doctor` report, `null` until it ran;
  /// [doctorRunning] is `true` while a report is being made, and [doctorError] is why the last
  /// run failed.
  const factory FlutterSdkState.completed({
    required FlutterSdk sdk,
    List<DoctorCheck>? checks,
    @Default(false) bool doctorRunning,
    Object? doctorError,
  }) = FlutterSdk$CompletedState;

  /// Reading the SDK failed with [error]. [sdk] and [checks] keep what was known before.
  const factory FlutterSdkState.error({
    required Object error,
    FlutterSdk? sdk,
    List<DoctorCheck>? checks,
  }) = FlutterSdk$ErrorState;
}

/// The Flutter SDK of the selected project and the `flutter doctor` report.
///
/// One thing at a time: a doctor run waits for a load that is in flight. A reload keeps the report
/// that was made, so switching projects does not blank the list.
final class FlutterSdkController extends StateController<FlutterSdkState>
    with SequentialControllerHandler {
  FlutterSdkController({
    required this._repository,
    super.initialState = const FlutterSdkState.initial(),
  });

  final IFlutterSdkRepository _repository;

  FlutterSdk? _sdk;
  List<DoctorCheck>? _checks;

  /// Reads the SDK that [projectPath] builds with; `null` describes the one on `PATH`.
  void load(String? projectPath) => handle(() async {
    if (isDisposed) return;
    if (_sdk == null) setState(const FlutterSdkState.inProgress());
    final sdk = await _repository.sdkFor(projectPath);
    if (isDisposed) return;
    setState(FlutterSdkState.completed(sdk: _sdk = sdk, checks: _checks));
  }, error: (error, stackTrace) async => setState(_failed(error)));

  /// Runs `flutter doctor`. Needs the SDK to be loaded first, and a `flutter` to run.
  ///
  /// A failed run keeps the SDK and the last report and puts its error in `doctorError`.
  void runDoctor() => handle(
    () async {
      final sdk = _sdk;
      final flutter = sdk?.path;
      if (isDisposed || sdk == null || flutter == null) return;
      setState(FlutterSdkState.completed(sdk: sdk, checks: _checks, doctorRunning: true));
      final checks = await _repository.doctor(flutter);
      if (isDisposed) return;
      setState(FlutterSdkState.completed(sdk: sdk, checks: _checks = checks));
    },
    error: (error, stackTrace) async {
      final sdk = _sdk;
      setState(
        sdk == null
            ? _failed(error)
            : FlutterSdkState.completed(sdk: sdk, checks: _checks, doctorError: error),
      );
    },
  );

  FlutterSdkState _failed(Object error) =>
      FlutterSdkState.error(error: error, sdk: _sdk, checks: _checks);
}
