import 'dart:io';

import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parseEnvOutput', () {
    test('ignores rc-file noise around the markers', () {
      final output = <String>[
        'Welcome!\n__FLUTTER_CODE_AGENT_ENV_START__',
        'PATH=/a:/b\u0000MULTI=line1\nline2\u0000EQ=a=b\u0000',
        '__FLUTTER_CODE_AGENT_ENV_END__bye',
      ].join();
      expect(ShellEnvironment.parseEnvOutput(output), <String, String>{
        'PATH': '/a:/b',
        'MULTI': 'line1\nline2',
        'EQ': 'a=b',
      });
    });

    test('returns null without markers', () {
      expect(ShellEnvironment.parseEnvOutput('PATH=/a'), isNull);
    });
  });

  test('fallback appends well-known tool directories once', () {
    final env = ShellEnvironment.fallback(<String, String>{'PATH': '/usr/bin:/opt/homebrew/bin'});
    expect(env.isFallback, isTrue);
    expect(env.variables['PATH'], '/usr/bin:/opt/homebrew/bin:/usr/local/bin');
  });

  group('resolve', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('shell_env_test'));
    tearDown(() => temp.deleteSync(recursive: true));

    File script(String body) {
      final file = File(p.join(temp.path, 'fake_shell.sh'))..writeAsStringSync('#!/bin/sh\n$body');
      Process.runSync('chmod', <String>['+x', file.path]);
      return file;
    }

    test('reads the environment printed by the shell', () async {
      // Ignores -ilc and runs the command the way a real shell would.
      final shell = script(r'shift; PATH=/custom/bin:/usr/bin FOO=bar /bin/sh -c "$1"');
      final env = await ShellEnvironment.resolve(shell: shell.path);
      expect(env.isFallback, isFalse);
      expect(env.variables['PATH'], '/custom/bin:/usr/bin');
      expect(env.variables['FOO'], 'bar');
    });

    test('falls back when the shell hangs', () async {
      final shell = script('sleep 30');
      final env = await ShellEnvironment.resolve(
        shell: shell.path,
        timeout: const Duration(milliseconds: 300),
      );
      expect(env.isFallback, isTrue);
      expect(env.variables['PATH'], contains('/opt/homebrew/bin'));
    });

    test('falls back when the shell does not exist', () async {
      final env = await ShellEnvironment.resolve(shell: p.join(temp.path, 'missing'));
      expect(env.isFallback, isTrue);
    });
  });

  test('which finds executables on PATH', () {
    const env = ShellEnvironment(<String, String>{'PATH': '/nonexistent:/bin'});
    expect(env.which('sh'), '/bin/sh');
    expect(env.which('definitely-not-a-binary'), isNull);
  });
}
