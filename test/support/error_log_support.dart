import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/_core/telemetry/telemetry.dart';
import 'package:flutter_code_agent/_core/utils/expected_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l/l.dart';

/// A gateway that sends nothing.
final class SilentGateway implements ICrashReportGateway {
  @override
  Future<bool> reachable() async => false;

  @override
  Future<bool> send(OutboxEntry entry) async => false;
}

/// The error log over an in-memory database; closed when the test ends.
TelemetryRuntime memoryRuntime() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = TelemetryDatabase.forTesting(NativeDatabase.memory());
  final runtime = TelemetryRuntime(
    db: db,
    gateway: SilentGateway(),
    appVersion: '1.0.0',
    platform: 'macos',
    projectPackages: const {'flutter_code_agent'},
    isExpected: isExpectedFailure,
  );
  addTearDown(() async {
    await runtime.sender.dispose();
    await db.close();
  });
  return runtime;
}

/// A test whose log output is swallowed: records reach `l.listen`, the test output stays pristine.
void quietTest(String description, Future<void> Function() body) => test(
  description,
  // ignore: experimental_member_use
  () => l.capture(body, const LogOptions(output: LogOutput.ignore, handlePrint: false)),
);
