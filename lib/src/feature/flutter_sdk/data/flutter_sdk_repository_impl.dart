import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
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
/// (`flutter --version --machine`) and the project's fvm pin. The `flutter doctor` report is
/// still made up: it needs the machine output of `flutter doctor`, which does not exist.
final class FlutterSdkRepositoryImpl implements IFlutterSdkRepository {
  /// Creates the repository. [which] finds an executable on `PATH` by name; [environment] is the
  /// environment `flutter` runs in (the login shell's, since a GUI app does not inherit it);
  /// [runProcess] starts it; [versionTimeout] is how long [sdkFor] waits for the version, since a
  /// cold or locked `flutter` can take long (or hang); [step] is the time "running" `flutter doctor`
  /// takes.
  FlutterSdkRepositoryImpl({
    required this._which,
    this._environment,
    this._runProcess = io.Process.run,
    this.versionTimeout = const Duration(seconds: 10),
    this.step = const Duration(milliseconds: 300),
  });

  final String? Function(String name) _which;
  final Map<String, String>? _environment;
  final ProcessRunner _runProcess;

  /// How long [sdkFor] waits for `flutter --version`; the process itself is not killed.
  final Duration versionTimeout;

  /// The time the made-up `flutter doctor` takes.
  final Duration step;

  @override
  Future<FlutterSdk> sdkFor(String? projectPath) async {
    final path = await pathFor(projectPath);
    final version = path == null ? null : await _versionOf(path);
    return FlutterSdk(
      path: path,
      version: version?.version,
      channel: version?.channel,
      fvmVersion: projectPath == null ? null : _fvmVersion(projectPath),
    );
  }

  @override
  Future<String?> pathFor(String? projectPath) async =>
      flutterExecutableFor(projectPath, which: _which);

  @override
  Future<List<DoctorCheck>> doctor() async {
    await Future<void>.delayed(step);
    return const <DoctorCheck>[
      DoctorCheck(title: 'Flutter', status: DoctorStatus.ok, detail: 'Channel stable, 3.27.1'),
      DoctorCheck(
        title: 'Android toolchain',
        status: DoctorStatus.warning,
        detail: 'cmdline-tools component is missing',
      ),
      DoctorCheck(title: 'Xcode', status: DoctorStatus.ok),
      DoctorCheck(title: 'Chrome', status: DoctorStatus.ok),
      DoctorCheck(title: 'Connected device', status: DoctorStatus.ok, detail: '2 available'),
      DoctorCheck(title: 'Network resources', status: DoctorStatus.ok),
    ];
  }

  /// The version and channel `flutter --version --machine` reports; `null` (and one log line)
  /// when the command fails or prints no JSON with them.
  ///
  /// `flutter` may print a banner before the JSON, so the text from the first `{` to the last
  /// `}` is parsed.
  Future<({String? version, String? channel})?> _versionOf(String flutter) async {
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
      return (version: version, channel: channel is String && channel.isNotEmpty ? channel : null);
    } on TimeoutException {
      l.w('Flutter SDK | $flutter --version did not finish in $versionTimeout');
    } on io.ProcessException catch (error, stackTrace) {
      l.w('Flutter SDK | cannot run $flutter --version: $error', stackTrace);
    } on FormatException catch (error, stackTrace) {
      l.w('Flutter SDK | cannot read the output of $flutter --version: $error', stackTrace);
    }
    return null;
  }

  /// The version the project pins with fvm ([fvmPinOf]); `null` when it pins none.
  String? _fvmVersion(String projectPath) => fvmPinOf(projectPath)?.version;
}
