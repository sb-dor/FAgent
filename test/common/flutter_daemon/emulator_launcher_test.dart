import 'dart:io';

import 'package:flutter_code_agent/src/common/flutter_daemon/emulator_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Runs [launchEmulatorDetached] against small shell scripts that stand in for `flutter`: no real
/// `flutter` or emulator is started.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('emulator_launcher_test'));
  tearDown(() => root.deleteSync(recursive: true));

  String script(String body) {
    final file = File(p.join(root.path, 'flutter'))..writeAsStringSync('#!/bin/sh\n$body\n');
    Process.runSync('chmod', <String>['+x', file.path]);
    return file.path;
  }

  test(
    'completes when the launcher exits with 0, with the arguments and the environment',
    () async {
      final out = p.join(root.path, 'out.txt');
      final flutter = script('echo "\$@ \$PROBE" > "$out"');

      await launchEmulatorDetached(
        flutter,
        'Pixel_9',
        environment: <String, String>{'PATH': '/usr/bin:/bin', 'PROBE': 'probe'},
      );

      expect(File(out).readAsStringSync().trim(), 'emulators --launch Pixel_9 probe');
    },
  );

  test('a non-zero exit throws with the code and the last output lines', () async {
    final flutter = script(
      'echo starting; echo "The Android emulator exited with code 1" >&2; exit 3',
    );

    await expectLater(
      launchEmulatorDetached(flutter, 'Pixel_9'),
      throwsA(
        isA<EmulatorLaunchException>()
            .having((error) => error.exitCode, 'exitCode', 3)
            .having((error) => error.output, 'output', contains('exited with code 1')),
      ),
    );
  });

  test('the launcher runs in a session of its own, not in the group of the app', () async {
    final out = p.join(root.path, 'group.txt');
    final flutter = script('ps -o pgid= -p \$\$ > "$out"');

    await launchEmulatorDetached(flutter, 'Pixel_9');

    final own = Process.runSync('ps', <String>['-o', 'pgid=', '-p', '$pid']).stdout.toString();
    expect(int.parse(File(out).readAsStringSync().trim()), isNot(int.parse(own.trim())));
  });
}
