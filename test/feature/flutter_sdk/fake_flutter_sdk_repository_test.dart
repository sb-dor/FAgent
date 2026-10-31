import 'dart:io';

import 'package:flutter_code_agent/src/feature/flutter_sdk/data/fake_flutter_sdk_repository.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  FakeFlutterSdkRepositoryImpl repository({String? path = '/opt/flutter/bin/flutter'}) =>
      FakeFlutterSdkRepositoryImpl(which: (_) => path, step: Duration.zero);

  void write(String relative, String text) {
    File(p.join(root.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() => root = Directory.systemTemp.createTempSync('flutter_sdk_test'));

  tearDown(() => root.deleteSync(recursive: true));

  group('sdkFor', () {
    test('reads the fvm version from .fvmrc', () async {
      write('.fvmrc', '{"flutter":"3.24.0"}');
      final sdk = await repository().sdkFor(root.path);
      expect(sdk.fvmVersion, '3.24.0');
      expect(sdk.path, '/opt/flutter/bin/flutter');
      expect(sdk.version, '3.27.1');
      expect(sdk.channel, 'stable');
      expect(sdk.isPreview, isTrue);
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

    test('a missing flutter executable gives no path', () async {
      expect((await repository(path: null).sdkFor(null)).path, isNull);
    });

    test('asks for flutter by name', () async {
      String? asked;
      final sdk = await FakeFlutterSdkRepositoryImpl(
        which: (name) {
          asked = name;
          return '/x/flutter';
        },
        step: Duration.zero,
      ).sdkFor(null);
      expect(asked, 'flutter');
      expect(sdk.path, '/x/flutter');
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
