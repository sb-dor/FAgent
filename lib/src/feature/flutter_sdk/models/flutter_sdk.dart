import 'package:freezed_annotation/freezed_annotation.dart';

part 'flutter_sdk.freezed.dart';

/// The Flutter SDK a project builds with, as the Settings screen shows it.
@freezed
abstract class FlutterSdk with _$FlutterSdk {
  /// Creates the description of an SDK.
  const factory FlutterSdk({
    /// Where the `flutter` executable is; `null` when none was found.
    String? path,

    /// The Flutter version, for example `3.27.1`.
    String? version,

    /// The channel of [version], for example `stable`.
    String? channel,

    /// The version the project pins with fvm; `null` when it does not use fvm.
    String? fvmVersion,

    /// Whether [version] and [channel] are made up.
    @Default(false) bool isPreview,
  }) = _FlutterSdk;
}

/// The verdict of one `flutter doctor` check.
enum DoctorStatus {
  /// Nothing to do.
  ok,

  /// Works, but something is missing.
  warning,

  /// Does not work.
  error,
}

/// One line of the `flutter doctor` report.
@freezed
abstract class DoctorCheck with _$DoctorCheck {
  /// Creates a check.
  const factory DoctorCheck({
    /// What was checked, for example `Android toolchain`.
    required String title,
    required DoctorStatus status,

    /// What the check found, for example what is missing.
    String? detail,
  }) = _DoctorCheck;
}
