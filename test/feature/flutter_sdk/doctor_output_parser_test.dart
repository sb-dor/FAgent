import 'package:flutter_code_agent/src/feature/flutter_sdk/data/doctor_output_parser.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

const _output = '''
Doctor summary (to see all details, run flutter doctor -v):
[✓] Flutter (Channel stable, 3.27.1, on macOS 15.1 24B83 darwin-arm64, locale en-US)
[!] Android toolchain - develop for Android devices (Android SDK version 34.0.0)
    ✗ cmdline-tools component is missing
      Run `path/to/sdkmanager --install "cmdline-tools;latest"`
[✓] Xcode - develop for iOS and macOS (Xcode 16.1)
[✗] Chrome - develop for the web (Cannot find Chrome executable at google-chrome)
    ! Cannot find Chrome. Try setting CHROME_EXECUTABLE to a Chrome executable.
[✓] Connected device (3 available)
[✓] Network resources
[☠] IntelliJ IDEA (the doctor check crashed)

! Doctor found issues in 3 categories.
''';

void main() {
  test('reads every check with its status and detail', () {
    expect(parseDoctorOutput(_output), const <DoctorCheck>[
      DoctorCheck(
        title: 'Flutter',
        status: DoctorStatus.ok,
        detail: 'Channel stable, 3.27.1, on macOS 15.1 24B83 darwin-arm64, locale en-US',
      ),
      DoctorCheck(
        title: 'Android toolchain',
        status: DoctorStatus.warning,
        detail: 'cmdline-tools component is missing',
      ),
      DoctorCheck(title: 'Xcode', status: DoctorStatus.ok, detail: 'Xcode 16.1'),
      DoctorCheck(
        title: 'Chrome',
        status: DoctorStatus.error,
        detail: 'Cannot find Chrome. Try setting CHROME_EXECUTABLE to a Chrome executable.',
      ),
      DoctorCheck(title: 'Connected device', status: DoctorStatus.ok, detail: '3 available'),
      DoctorCheck(title: 'Network resources', status: DoctorStatus.ok),
      DoctorCheck(
        title: 'IntelliJ IDEA',
        status: DoctorStatus.error,
        detail: 'the doctor check crashed',
      ),
    ]);
  });

  test('empty output has no checks', () {
    expect(parseDoctorOutput(''), isEmpty);
  });

  test('strips ANSI escapes', () {
    final checks = parseDoctorOutput('\x1B[32m[✓] Flutter (Channel stable, 3.27.1)\x1B[0m\n');
    expect(checks, const <DoctorCheck>[
      DoctorCheck(title: 'Flutter', status: DoctorStatus.ok, detail: 'Channel stable, 3.27.1'),
    ]);
  });
}
