import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:flutter_code_agent/src/feature/initialization/data/error_log_step.dart';
import 'package:flutter_code_agent/src/feature/initialization/data/initialize_dependencies.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/error_log_support.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late List<String> console;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fagent_error_log_');
    console = <String>[];
    ErrorUtil.reset();
    ErrorUtil.console = console.add;
    addTearDown(() => dir.deleteSync(recursive: true));
    addTearDown(ErrorUtil.reset);
  });

  test('the first step is "Error log", with a closer', () {
    expect(initializationStepsForTest.keys.first, 'Error log');
    expect(initializationClosersForTest.keys, contains('Error log'));
  });

  quietTest('the log opens, closing it twice is safe', () async {
    final dependencies = Dependencies();

    await startErrorLog(dependencies, supportDirectory: () async => dir);

    expect(dependencies.telemetryRuntime, isNotNull);
    expect(File('${dir.path}/logs.sqlite').existsSync(), isTrue);
    await dependencies.closeErrorLog();
    await dependencies.closeErrorLog();
    expect(console, isEmpty);
  });

  quietTest(
    'a directory that cannot be created leaves the runtime null, the steps go on',
    () async {
      final blocker = File('${dir.path}/occupied')..writeAsStringSync('file');
      final ran = <String>[];

      final dependencies = await $initializeDependencies(
        steps: {
          'Error log': (d) =>
              startErrorLog(d, supportDirectory: () async => Directory('${blocker.path}/inside')),
          'Next': (_) => ran.add('Next'),
        },
        closers: {},
      );

      expect(dependencies.telemetryRuntime, isNull);
      expect(ran, ['Next']);
      expect(console.join('\n'), contains('error log is unavailable'));
      await dependencies.closeErrorLog();
    },
  );
}
