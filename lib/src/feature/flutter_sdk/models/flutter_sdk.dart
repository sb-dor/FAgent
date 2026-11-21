import 'dart:async';

import 'package:flutter_code_agent/src/common/utils/expected_exception.dart';
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

    /// The Dart version of the SDK, for example `3.6.0`.
    String? dartVersion,

    /// The version the project pins with fvm; `null` when it does not use fvm.
    String? fvmVersion,

    /// Whether [version] and [channel] are made up.
    @Default(false) bool isPreview,
  }) = _FlutterSdk;
}

/// `flutter doctor` failed without a report: it exited with [exitCode] and printed [output]
/// (stderr, else stdout) instead of checks.
///
/// It is the SDK's setup, not a bug of the app.
final class FlutterDoctorFailedException extends ExpectedException {
  /// Creates the exception.
  const FlutterDoctorFailedException(this.exitCode, this.output);

  /// The exit code of `flutter doctor`.
  final int exitCode;

  /// What `flutter doctor` printed.
  final String output;

  @override
  String toString() => 'FlutterDoctorFailedException($exitCode): $output';
}

/// `flutter doctor` did not finish within [duration] and was killed.
///
/// A cold or locked SDK, not a bug of the app; it reads as any other timeout.
final class FlutterDoctorTimeoutException extends ExpectedException implements TimeoutException {
  /// Creates the exception.
  const FlutterDoctorTimeoutException(this.duration);

  @override
  final Duration duration;

  @override
  String get message => 'flutter doctor did not finish';

  @override
  String toString() =>
      'FlutterDoctorTimeoutException: flutter doctor did not finish within ${duration.inSeconds} s';
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
