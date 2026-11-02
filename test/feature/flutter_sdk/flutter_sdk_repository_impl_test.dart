import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  const versionJson = '{"frameworkVersion":"3.47.1","channel":"stable"}';

  /// The commands the repository ran, as `executable arguments`.
  late List<String> ran;

  ProcessRunner runner({String stdout = versionJson, int exitCode = 0}) =>
      (executable, arguments, {environment}) async {
        ran.add('$executable ${arguments.join(' ')}');
        return ProcessResult(1, exitCode, stdout, '');
      };

  FlutterSdkRepositoryImpl repository({
    String? path = '/opt/flutter/bin/flutter',
    ProcessRunner? runProcess,
    Map<String, String>? environment,
    Duration versionTimeout = const Duration(seconds: 10),
  }) => FlutterSdkRepositoryImpl(
    which: (_) => path,
    environment: environment,
    runProcess: runProcess ?? runner(),
    versionTimeout: versionTimeout,
    step: Duration.zero,
  );

  void write(String relative, String text) {
    File(p.join(root.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('flutter_sdk_test');
    ran = <String>[];
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('sdkFor', () {
    test('reads the fvm version from .fvmrc', () async {
      write('.fvmrc', '{"flutter":"3.24.0"}');
      final sdk = await repository().sdkFor(root.path);
      expect(sdk.fvmVersion, '3.24.0');
    });

    test('a pinned project without its fvm SDK has no path and runs nothing', () async {
      write('.fvmrc', '{"flutter":"3.24.0"}');
      final sdk = await repository().sdkFor(root.path);
      expect(sdk.path, isNull);
      expect(sdk.version, isNull);
      expect(ran, isEmpty);
    });

    test('a project with its fvm SDK reports the version of that SDK', () async {
      write('.fvmrc', '{"flutter":"3.24.0"}');
      write('.fvm/flutter_sdk/bin/flutter', '');
      final sdk = await repository().sdkFor(root.path);
      final flutter = p.join(root.path, '.fvm', 'flutter_sdk', 'bin', 'flutter');
      expect(sdk.path, flutter);
      expect(sdk.version, '3.47.1');
      expect(ran, <String>['$flutter --version --machine']);
    });

    test('reads version and channel', () async {
      final sdk = await repository().sdkFor(null);
      expect(sdk.version, '3.47.1');
      expect(sdk.channel, 'stable');
      expect(sdk.isPreview, isFalse);
      expect(ran, <String>['/opt/flutter/bin/flutter --version --machine']);
    });

    test('passes the environment to flutter', () async {
      Map<String, String>? passed;
      final sdk = await repository(
        environment: <String, String>{'PATH': '/bin'},
        runProcess: (executable, arguments, {environment}) async {
          passed = environment;
          return ProcessResult(1, 0, versionJson, '');
        },
      ).sdkFor(null);
      expect(sdk.version, '3.47.1');
      expect(passed, <String, String>{'PATH': '/bin'});
    });

    test('skips lines before the JSON', () async {
      final sdk = await repository(
        runProcess: runner(stdout: 'Waiting for another flutter command...\n$versionJson\n'),
      ).sdkFor(null);
      expect(sdk.version, '3.47.1');
      expect(sdk.channel, 'stable');
    });

    test('failed command has no version', () async {
      final sdk = await repository(runProcess: runner(exitCode: 1)).sdkFor(null);
      expect(sdk.path, '/opt/flutter/bin/flutter');
      expect(sdk.version, isNull);
      expect(sdk.channel, isNull);
      expect(sdk.isPreview, isFalse);
    });

    test('bad JSON has no version', () async {
      final sdk = await repository(runProcess: runner(stdout: 'not json {')).sdkFor(null);
      expect(sdk.version, isNull);
      expect(sdk.channel, isNull);
    });

    test('JSON without the keys has no version', () async {
      final sdk = await repository(runProcess: runner(stdout: '{"other":1}')).sdkFor(null);
      expect(sdk.version, isNull);
      expect(sdk.channel, isNull);
    });

    test('a command that cannot start has no version', () async {
      final sdk = await repository(
        runProcess: (executable, arguments, {environment}) =>
            throw const ProcessException('flutter', <String>[], 'no such file'),
      ).sdkFor(null);
      expect(sdk.path, '/opt/flutter/bin/flutter');
      expect(sdk.version, isNull);
    });

    test('version call that never completes times out', () async {
      final sdk = await repository(
        runProcess: (executable, arguments, {environment}) => Completer<ProcessResult>().future,
        versionTimeout: const Duration(milliseconds: 10),
      ).sdkFor(null);
      expect(sdk.path, '/opt/flutter/bin/flutter');
      expect(sdk.version, isNull);
      expect(sdk.channel, isNull);
    });

    test('no flutter has no path and runs nothing', () async {
      final sdk = await repository(path: null).sdkFor(null);
      expect(sdk.path, isNull);
      expect(sdk.version, isNull);
      expect(sdk.channel, isNull);
      expect(ran, isEmpty);
    });

    test('falls back to .fvm/fvm_config.json', () async {
      write('.fvm/fvm_config.json', '{"flutterSdkVersion":"3.22.1"}');
      expect((await repository().sdkFor(root.path)).fvmVersion, '3.22.1');
    });

    test('.fvmrc wins over fvm_config.json', () async {
      write('.fvmrc', '{"flutter":"3.24.0"}');
      write('.fvm/fvm_config.json', '{"flutterSdkVersion":"3.22.1"}');
      expect((await repository().sdkFor(root.path)).fvmVersion, '3.24.0');
    });

    test('a broken .fvmrc gives no version', () async {
      write('.fvmrc', '{"flutter":');
      expect((await repository().sdkFor(root.path)).fvmVersion, isNull);
    });

    test('a .fvmrc without the key gives no version', () async {
      write('.fvmrc', '{"other":"1"}');
      expect((await repository().sdkFor(root.path)).fvmVersion, isNull);
    });

    test('a project without fvm has no version', () async {
      expect((await repository().sdkFor(root.path)).fvmVersion, isNull);
    });

    test('no project has no version', () async {
      expect((await repository().sdkFor(null)).fvmVersion, isNull);
    });

    test('asks for flutter by name', () async {
      String? asked;
      final sdk = await FlutterSdkRepositoryImpl(
        which: (name) {
          asked = name;
          return '/x/flutter';
        },
        runProcess: runner(),
        step: Duration.zero,
      ).sdkFor(null);
      expect(asked, 'flutter');
      expect(sdk.path, '/x/flutter');
    });
  });

  group('pathFor', () {
    test('finds flutter and runs nothing', () async {
      expect(await repository().pathFor(null), '/opt/flutter/bin/flutter');
      expect(ran, isEmpty);
    });

    test('no flutter gives no path', () async {
      expect(await repository(path: null).pathFor(null), isNull);
    });

    test('a pinned project without its fvm SDK gives no path', () async {
      write('.fvmrc', '{"flutter":"3.24.0"}');
      expect(await repository().pathFor(root.path), isNull);
      expect(ran, isEmpty);
    });

    test('a project with its fvm SDK gives that SDK', () async {
      write('.fvm/flutter_sdk/bin/flutter', '');
      expect(
        await repository().pathFor(root.path),
        p.join(root.path, '.fvm', 'flutter_sdk', 'bin', 'flutter'),
      );
      expect(ran, isEmpty);
    });
  });

  group('doctor', () {
    test('reports six checks, the second a warning', () async {
      final checks = await repository().doctor();
      expect(checks, hasLength(6));
      expect(checks[1].title, 'Android toolchain');
      expect(checks[1].status, DoctorStatus.warning);
      expect(checks[1].detail, 'cmdline-tools component is missing');
      expect(checks.where((check) => check.status == DoctorStatus.ok), hasLength(5));
    });
  });
}
