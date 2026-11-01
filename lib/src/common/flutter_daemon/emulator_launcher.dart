import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;

/// Boots the emulator [emulatorId] with the `flutter` [executable]; completes once the emulator
/// is on its way and throws when it could not be started. Tests substitute one that spawns
/// nothing.
typedef EmulatorLauncher = Future<void> Function(
  String executable,
  String emulatorId, {
  Map<String, String>? environment,
});

/// {@template emulator_launch_exception}
/// `flutter emulators --launch` failed: it exited with [exitCode] (`null` when it never reported
/// one) after printing [output] (its last lines).
/// {@endtemplate}
final class EmulatorLaunchException implements Exception {
  /// {@macro emulator_launch_exception}
  const EmulatorLaunchException({required this.exitCode, required this.output});

  /// The exit code, or `null` when the launcher ended without one.
  final int? exitCode;

  /// The last lines the launcher printed (stdout and stderr together).
  final String output;

  @override
  String toString() =>
      'EmulatorLaunchException: flutter emulators --launch '
      '${exitCode == null ? 'ended without an exit code' : 'exited with code $exitCode'}'
      '${output.isEmpty ? '' : '\n$output'}';
}

const String _exitMarker = '__FLUTTER_CODE_AGENT_EXIT__';

/// How many of the last output lines an [EmulatorLaunchException] keeps.
const int _outputLines = 20;

/// Boots [emulatorId] with `flutter emulators --launch` started as a **detached** process.
///
/// flutter_tools starts the emulator as a child of the `flutter` that launches it. Inside the
/// `flutter daemon` that child would share the daemon's process group and die with it when the
/// app quits; detached, `flutter` runs in a session of its own, so the emulator outlives the app
/// the way one booted from a terminal does.
///
/// Dart reports no exit code for a detached process, so `/bin/sh` runs the command and prints its
/// status on the last line. `flutter emulators --launch` exits a few seconds after the emulator
/// started; a non-zero status, an output that ends without the status or no status within
/// [timeout] throws [EmulatorLaunchException] (a [TimeoutException] for the last).
Future<void> launchEmulatorDetached(
  String executable,
  String emulatorId, {
  Map<String, String>? environment,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final process = await io.Process.start(
    '/bin/sh',
    <String>[
      '-c',
      // "$0" "$@" keep every argument intact; 2>&1 gives one stream to read.
      '"\$0" "\$@" 2>&1; echo "$_exitMarker \$?"',
      executable,
      'emulators',
      '--launch',
      emulatorId,
    ],
    environment: environment,
    includeParentEnvironment: environment == null,
    mode: io.ProcessStartMode.detachedWithStdio,
  );
  unawaited(process.stdin.close().then<void>((_) {}, onError: (Object _) {}));
  process.stderr.drain<void>().ignore();
  final output = ListQueue<String>();
  final status = Completer<int?>();
  final subscription = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .listen(
        (line) {
          if (line.startsWith(_exitMarker)) {
            if (!status.isCompleted) {
              status.complete(int.tryParse(line.substring(_exitMarker.length).trim()));
            }
            return;
          }
          output.add(line);
          if (output.length > _outputLines) output.removeFirst();
        },
        onError: (Object _) {},
        onDone: () {
          if (!status.isCompleted) status.complete(null);
        },
      );
  try {
    final code = await status.future.timeout(timeout);
    if (code != 0) throw EmulatorLaunchException(exitCode: code, output: output.join('\n'));
  } finally {
    // The status is all that is needed; a leftover of `flutter` may keep the pipe open.
    await subscription.cancel();
  }
}
