import 'dart:io';

import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory project;

  setUp(() => project = Directory.systemTemp.createTempSync('flutter_executable_test'));
  tearDown(() => project.deleteSync(recursive: true));

  String? which(String name) => name == 'flutter' ? '/usr/local/bin/flutter' : null;

  test('prefers the fvm SDK of the project', () {
    final fvm = File(p.join(project.path, '.fvm', 'flutter_sdk', 'bin', 'flutter'))
      ..createSync(recursive: true);

    expect(flutterExecutableFor(project.path, which: which), fvm.path);
  });

  test('falls back to which when the project has no fvm SDK', () {
    expect(flutterExecutableFor(project.path, which: which), '/usr/local/bin/flutter');
  });

  test('falls back to which without a project', () {
    expect(flutterExecutableFor(null, which: which), '/usr/local/bin/flutter');
  });

  test('is null when there is no Flutter at all', () {
    expect(flutterExecutableFor(project.path, which: (_) => null), isNull);
  });

  void write(String path, String text) => File(p.join(project.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  test('a project that pins a version without its fvm SDK has no flutter', () {
    write('.fvmrc', '{"flutter":"3.24.0"}');

    expect(flutterExecutableFor(project.path, which: which), isNull);
    expect(
      flutterNotFoundMessage(project.path),
      'This project pins Flutter 3.24.0 with fvm, but it is not installed. '
      'Run `fvm install` in the project folder.',
    );
  });

  test('an older fvm config pins the version too', () {
    write('.fvm/fvm_config.json', '{"flutterSdkVersion":"3.22.1"}');

    expect(flutterExecutableFor(project.path, which: which), isNull);
    expect(flutterNotFoundMessage(project.path), contains('pins Flutter 3.22.1 with fvm'));
  });

  test('a pin whose version cannot be read still pins, without the version', () {
    write('.fvmrc', 'not json');

    expect(flutterExecutableFor(project.path, which: which), isNull);
    expect(flutterNotFoundMessage(project.path), startsWith('This project pins Flutter with fvm'));
  });

  test('a pinned project with its fvm SDK uses it', () {
    write('.fvmrc', '{"flutter":"3.24.0"}');
    final fvm = File(p.join(project.path, '.fvm', 'flutter_sdk', 'bin', 'flutter'))
      ..createSync(recursive: true);

    expect(flutterExecutableFor(project.path, which: which), fvm.path);
  });

  test('without a pin the message points at the PATH', () {
    expect(flutterNotFoundMessage(project.path), contains('PATH'));
    expect(flutterNotFoundMessage(null), contains('PATH'));
  });

  test('fvmPinOf reads .fvmrc before .fvm/fvm_config.json', () {
    expect(fvmPinOf(project.path), isNull);
    write('.fvm/fvm_config.json', '{"flutterSdkVersion":"3.22.1"}');
    expect(fvmPinOf(project.path)?.version, '3.22.1');
    write('.fvmrc', '{"flutter":"3.24.0"}');
    expect(fvmPinOf(project.path)?.version, '3.24.0');
  });

  test('a dangling fvm symlink does not count', () {
    final bin = Directory(p.join(project.path, '.fvm', 'flutter_sdk', 'bin'))
      ..createSync(recursive: true);
    Link(p.join(bin.path, 'flutter')).createSync(p.join(project.path, 'nowhere'));

    expect(flutterExecutableFor(project.path, which: which), '/usr/local/bin/flutter');
  });
}
