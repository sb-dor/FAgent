import 'dart:io' as io;

/// A `ProcessRunner` for `FlutterSdkRepositoryImpl` that answers `flutter --version --machine`
/// with Flutter 3.27.1 on stable and starts no process.
Future<io.ProcessResult> flutterVersionRunner(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async => io.ProcessResult(1, 0, '{"frameworkVersion":"3.27.1","channel":"stable"}', '');
