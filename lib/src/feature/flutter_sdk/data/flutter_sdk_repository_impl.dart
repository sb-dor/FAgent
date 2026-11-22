import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
import 'package:flutter_code_agent/src/common/process/run_process.dart';
import 'package:flutter_code_agent/src/common/telemetry/hidden_details_error.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/doctor_output_parser.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:l/l.dart';

/// Runs [executable] with [arguments] to the end, like [io.Process.run]; a test passes its own.
typedef ProcessRunner = Future<io.ProcessResult> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

/// The Flutter SDK of a project, read from the machine: the path of `flutter`, the version
/// (`flutter --version --machine`), the project's fvm pin and the `flutter doctor` report.
final class FlutterSdkRepositoryImpl implements IFlutterSdkRepository {
  /// Creates the repository. [which] finds an executable on `PATH` by name; [environment] is the
  /// environment `flutter` runs in (the login shell's, since a GUI app does not inherit it);
  /// [runProcess] starts it; [versionTimeout] is how long [sdkFor] waits for the version, since a
  /// cold or locked `flutter` can take long (or hang); [runDoctor] runs `flutter doctor` and kills it
  /// when [doctorTimeout] passes.
  FlutterSdkRepositoryImpl({
    required this._which,
    this._environment,
    this._runProcess = io.Process.run,
    this._runDoctor = runProcessKillingOnTimeout,
    this.versionTimeout = const Duration(seconds: 10),
    this.doctorTimeout = const Duration(minutes: 2),
  });

  final String? Function(String name) _which;
  final Map<String, String>? _environment;
  final ProcessRunner _runProcess;
  final TimedProcessRunner _runDoctor;

  /// How long [sdkFor] waits for `flutter --version`; the process itself is not killed.
  final Duration versionTimeout;

  /// How long [doctor] waits for `flutter doctor`; a process that runs longer is killed.
  final Duration doctorTimeout;

  @override
  Future<FlutterSdk> sdkFor(String? projectPath) async {
    final path = await pathFor(projectPath);
    final version = path == null ? null : await _versionOf(path);
    return FlutterSdk(
      path: path,
      version: version?.version,
      channel: version?.channel,
      dartVersion: version?.dartVersion,
      fvmVersion: projectPath == null ? null : _fvmVersion(projectPath),
    );
  }

  @override
  Future<String?> pathFor(String? projectPath) async =>
      flutterExecutableFor(projectPath, which: _which);

  /// `flutter doctor` exits with 1 when it finds a problem, so a report with checks is returned
  /// whatever the exit code. A failure that printed no check (a broken SDK) throws a
  /// [FlutterDoctorFailedException], a timeout a [FlutterDoctorTimeoutException]; a process that
  /// cannot start throws too.
  @override
  Future<List<DoctorCheck>> doctor(String flutter) async {
    final io.ProcessResult result;
    try {
      result = await _runDoctor(
        flutter,
        const <String>['doctor'],
        environment: _environment,
        timeout: doctorTimeout,
      );
    } on TimeoutException catch (_, stackTrace) {
      Error.throwWithStackTrace(FlutterDoctorTimeoutException(doctorTimeout), stackTrace);
    }
    final checks = parseDoctorOutput('${result.stdout}');
    if (checks.isEmpty && result.exitCode != 0) {
      final stderr = '${result.stderr}'.trim();
      throw FlutterDoctorFailedException(
        result.exitCode,
        stderr.isNotEmpty ? stderr : '${result.stdout}'.trim(),
      );
    }
    return checks;
  }

  /// The version, channel and Dart version `flutter --version --machine` reports; `null` (and one log line)
  /// when the command fails or prints no JSON with them.
  ///
  /// `flutter` may print a banner before the JSON, so the text from the first `{` to the last
  /// `}` is parsed.
  Future<({String? version, String? channel, String? dartVersion})?> _versionOf(
    String flutter,
  ) async {
    try {
      final result = await _runProcess(flutter, const <String>[
        '--version',
        '--machine',
      ], environment: _environment).timeout(versionTimeout);
      if (result.exitCode != 0) {
        l.w('Flutter SDK | $flutter --version exited with ${result.exitCode}');
        return null;
      }
      final output = '${result.stdout}';
      final start = output.indexOf('{');
      final end = output.lastIndexOf('}');
      final json = start >= 0 && end > start ? jsonDecode(output.substring(start, end + 1)) : null;
      final version = json is Map<String, Object?> ? json['frameworkVersion'] : null;
      if (version is! String || version.isEmpty) {
        l.w('Flutter SDK | $flutter --version printed no frameworkVersion');
        return null;
      }
      final channel = json is Map<String, Object?> ? json['channel'] : null;
      final dart = json is Map<String, Object?> ? json['dartSdkVersion'] : null;
      final dartVersion = dart is String ? dart.split(' ').first : null;
      return (
        version: version,
        channel: channel is String && channel.isNotEmpty ? channel : null,
        dartVersion: dartVersion == null || dartVersion.isEmpty ? null : dartVersion,
      );
    } on TimeoutException {
      l.w('Flutter SDK | $flutter --version did not finish in $versionTimeout');
    } on io.ProcessException catch (error, stackTrace) {
      l.w('Flutter SDK | cannot run $flutter --version: ${hideDataDetails(error)}', stackTrace);
    } on FormatException catch (error, stackTrace) {
      l.w(
        'Flutter SDK | cannot read the output of $flutter --version: ${hideDataDetails(error)}',
        stackTrace,
      );
    }
    return null;
  }

  /// The version the project pins with fvm ([fvmPinOf]); `null` when it pins none.
  String? _fvmVersion(String projectPath) => fvmPinOf(projectPath)?.version;
}
