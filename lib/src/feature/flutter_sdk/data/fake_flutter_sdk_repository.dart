import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';

/// Made-up Flutter version and `flutter doctor` report until the Flutter tooling is wired in
/// (milestone M4). The SDK path and the project's fvm version are real: they are found on the
/// machine.
final class FakeFlutterSdkRepositoryImpl implements IFlutterSdkRepository {
  /// Creates the repository. [which] finds an executable on `PATH` by name; [step] is the time
  /// "running" `flutter doctor` takes.
  FakeFlutterSdkRepositoryImpl({
    required this._which,
    this.step = const Duration(milliseconds: 300),
  });

  final String? Function(String name) _which;

  /// The time one operation takes.
  final Duration step;

  @override
  Future<FlutterSdk> sdkFor(String? projectPath) async => FlutterSdk(
    path: _which('flutter'),
    version: '3.27.1',
    channel: 'stable',
    fvmVersion: projectPath == null ? null : _fvmVersion(projectPath),
    isPreview: true,
  );

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

  /// The version the project pins with fvm ([fvmPinOf]); `null` when it pins none.
  String? _fvmVersion(String projectPath) => fvmPinOf(projectPath)?.version;
}
