import 'dart:io' as io;

/// The report `flutter doctor` prints in [flutterVersionRunner].
const String flutterDoctorReport = '''
Doctor summary (to see all details, run flutter doctor -v):
[✓] Flutter (Channel stable, 3.27.1, on macOS 15.1 24B83 darwin-arm64, locale en-US)
[!] Android toolchain - develop for Android devices (Android SDK version 34.0.0)
    ✗ cmdline-tools component is missing
[✓] Xcode - develop for iOS and macOS (Xcode 16.1)
[✓] Chrome - develop for the web
[✓] Connected device (2 available)
[✓] Network resources

! Doctor found issues in 1 category.
''';

/// A `ProcessRunner` for `FlutterSdkRepositoryImpl` that answers `flutter --version --machine`
/// with Flutter 3.27.1 on stable and `flutter doctor` with [flutterDoctorReport]; it starts no
/// process.
Future<io.ProcessResult> flutterVersionRunner(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async => arguments.contains('doctor')
    ? io.ProcessResult(1, 1, flutterDoctorReport, '')
    : io.ProcessResult(1, 0, '{"frameworkVersion":"3.27.1","channel":"stable"}', '');
