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

  test('a dangling fvm symlink does not count', () {
    final bin = Directory(p.join(project.path, '.fvm', 'flutter_sdk', 'bin'))
      ..createSync(recursive: true);
    Link(p.join(bin.path, 'flutter')).createSync(p.join(project.path, 'nowhere'));

    expect(flutterExecutableFor(project.path, which: which), '/usr/local/bin/flutter');
  });
}
