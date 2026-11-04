import 'dart:io';

import 'package:flutter_code_agent/src/feature/app_run/data/launch_config_reader.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/build_mode.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/launch_config.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const root = '/work/app';

  /// A launch.json with one dart launch configuration made of [fields].
  String single(String fields) =>
      '{"configurations": [{"name": "c", "type": "dart", "request": "launch", $fields}]}';

  List<LaunchConfig> read(String text) {
    final result = parseLaunchConfigs(text, projectRoot: root);
    expect(result, isA<LaunchConfigsRead>());
    return (result as LaunchConfigsRead).configs;
  }

  LaunchConfig readOne(String fields) => read(single(fields)).single;

  group('parseLaunchConfigs', () {
    test("the user's launch.json gives seven configs in order with their flavor, file-define in "
        'extra args and device', () {
      final text = File('test/fixtures/launch_json/user_launch.json').readAsStringSync();
      final configs = read(text);

      expect(configs.map((config) => config.name), <String>[
        'Run DEV App (Debug with release json)',
        'Run Profit7 App (Debug with release json)',
        'Run DEV App (Debug)',
        'Run Profit7 App (Debug)',
        'Run DEV App (Debug, Drop database)',
        'Run DEV App (Debug, Memmory database)',
        'Run DEV Web Server (Debug)',
      ]);
      expect(configs[0].flavor, 'avera');
      expect(configs[0].extraArgs, '--dart-define-from-file=config/avera/production.json');
      expect(configs[1].flavor, 'profit7');
      expect(configs[1].extraArgs, '--dart-define-from-file=config/profit7/production.json');
      expect(configs[4].flavor, isNull);
      expect(configs[4].dartDefines, <String>['DROP_DATABASE=true']);
      expect(configs[4].extraArgs, '--dart-define-from-file=config/avera/development.json');
      expect(configs[5].dartDefines, <String>['IN_MEMORY_DATABASE=true']);
      expect(configs[6].name, 'Run DEV Web Server (Debug)');
      expect(configs[6].deviceId, 'web-server');
      expect(configs[6].extraArgs, '--dart-define-from-file=config/avera/development.json');
      for (final config in configs) {
        expect(config.target, 'lib/main.dart');
        expect(config.unsupported, isNull);
        expect(config.hasPreLaunchTask, isFalse);
        expect(config.environment, isEmpty);
        expect(config.mode, isNull);
        if (config != configs[6]) expect(config.deviceId, isNull);
      }
    });

    test('comments and trailing commas are accepted', () {
      final configs = read('''
// a leading comment
{
  /* block
     comment */
  "version": "0.2.0", // trailing
  "configurations": [
    {
      "name": "a", "type": "dart", "request": "launch", // note
      "args": ["--flavor=x", /* gone */ ],
    }, // between
  ], /* before the end */
}
''');
      expect(configs.single.name, 'a');
      expect(configs.single.flavor, 'x');
    });

    test('comment markers inside strings are kept, including URLs and escaped quotes', () {
      final config = readOne(
        '"args": ["--dart-define=API=https://example.com/a//b", "--dart-define=S=/* x */", '
        r'"--dart-define=Q=say \"hi\" // not a comment"]',
      );
      expect(config.dartDefines, <String>[
        'API=https://example.com/a//b',
        'S=/* x */',
        'Q=say "hi" // not a comment',
      ]);
    });

    test('a comma inside a string before a closing bracket is kept', () {
      final config = readOne('"args": ["--dart-define=L=a,]", "--dart-define=M=b,}"]');
      expect(config.dartDefines, <String>['L=a,]', 'M=b,}']);
    });

    test('a string ending in an escaped backslash does not swallow the next quote', () {
      final config = readOne(r'"args": ["--dart-define=P=c:\\", "--dart-define=Q=1"]');
      expect(config.dartDefines, <String>[r'P=c:\', 'Q=1']);
    });

    test('other types and attach requests are skipped', () {
      final configs = read('''
{"configurations": [
  {"name": "node", "type": "node", "request": "launch"},
  {"name": "attach", "type": "dart", "request": "attach"},
  {"name": "no request", "type": "dart"},
  {"name": "ok", "type": "dart", "request": "launch"},
]}
''');
      expect(configs.map((config) => config.name), <String>['ok']);
    });

    test('a file without configurations has none', () {
      expect(read('{"version": "0.2.0"}'), isEmpty);
      expect(read('{"version": "0.2.0", "configurations": []}'), isEmpty);
    });

    test('program defaults to lib/main.dart and stays relative', () {
      expect(readOne('"program": "lib/other.dart"').target, 'lib/other.dart');
      expect(readOne('"name": "c"').target, 'lib/main.dart');
    });

    test('${r'${workspaceFolder}'} in program and cwd is the project folder', () {
      final config = readOne(
        r'"program": "${workspaceFolder}/lib/main_dev.dart", "cwd": "${workspaceFolder}"',
      );
      expect(config.target, 'lib/main_dev.dart');
      expect(config.unsupported, isNull);
      expect(readOne(r'"cwd": "${workspaceFolder}/"').unsupported, isNull);
      expect(readOne('"cwd": "$root"').unsupported, isNull);
      expect(readOne('"name": "c"').unsupported, isNull);
    });

    test('${r'${workspaceFolder}'} in args is the project folder', () {
      final config = readOne(r'"args": ["--dart-define-from-file=${workspaceFolder}/c.json"]');
      expect(config.extraArgs, '--dart-define-from-file=$root/c.json');
      expect(config.unsupported, isNull);
    });

    test('another variable makes the config unsupported with its name', () {
      final inProgram = readOne(r'"program": "${env:HOME}/main.dart"');
      expect(inProgram.unsupported, contains(r'${env:HOME}'));
      final inArgs = readOne(r'"args": ["--dart-define=A=${command:pickX}"]');
      expect(inArgs.unsupported, contains(r'${command:pickX}'));
      final inEnv = readOne(r'"env": {"A": "${userHome}"}');
      expect(inEnv.unsupported, contains(r'${userHome}'));
      final inCwd = readOne(r'"cwd": "${fileDirname}"');
      expect(inCwd.unsupported, contains(r'${fileDirname}'));
    });

    test('a cwd outside the project is unsupported', () {
      final config = readOne(r'"cwd": "${workspaceFolder}/packages/core"');
      expect(config.unsupported, isNotNull);
      expect(config.unsupported, contains('packages/core'));
      expect(readOne('"cwd": "/somewhere/else"').unsupported, isNotNull);
    });

    test('deviceId and flutterMode keys', () {
      final config = readOne('"deviceId": "macos", "flutterMode": "profile"');
      expect(config.deviceId, 'macos');
      expect(config.mode, BuildMode.profile);
      expect(readOne('"flutterMode": "release"').mode, BuildMode.release);
      expect(readOne('"flutterMode": "debug"').mode, BuildMode.debug);
      expect(readOne('"flutterMode": "nonsense"').mode, isNull);
    });

    test('--release in args sets the mode', () {
      final config = readOne('"args": ["--release", "--verbose"]');
      expect(config.mode, BuildMode.release);
      expect(config.extraArgs, '--verbose');
      expect(readOne('"args": ["--profile"]').mode, BuildMode.profile);
      expect(readOne('"args": ["--debug"]').mode, BuildMode.debug);
    });

    test('device flags in args set the device', () {
      expect(readOne('"args": ["-d", "ios"]').deviceId, 'ios');
      expect(readOne('"args": ["--device-id", "ios"]').deviceId, 'ios');
      expect(readOne('"args": ["--device-id=ios"]').deviceId, 'ios');
      expect(readOne('"args": ["-d", "ios"]').extraArgs, isEmpty);
    });

    test('--flavor=x and --flavor x both', () {
      expect(readOne('"args": ["--flavor=x"]').flavor, 'x');
      final spaced = readOne('"args": ["--flavor", "x", "--verbose"]');
      expect(spaced.flavor, 'x');
      expect(spaced.extraArgs, '--verbose');
    });

    test('--dart-define=K=V and --dart-define K=V both, in order', () {
      final config = readOne('"args": ["--dart-define=A=1", "--dart-define", "B=2"]');
      expect(config.dartDefines, <String>['A=1', 'B=2']);
      expect(config.extraArgs, isEmpty);
    });

    test('toolArgs are split like args', () {
      final config = readOne('"args": ["--flavor=a"], "toolArgs": ["--release", "-d", "web"]');
      expect(config.flavor, 'a');
      expect(config.mode, BuildMode.release);
      expect(config.deviceId, 'web');
    });

    test('the remaining args stay in order and survive splitArgs', () {
      final config = readOne(
        r'"args": ["--a", "--flavor=f", "two words", "--dart-define=X=1", "q\"uote", "", "back\\slash"]',
      );
      expect(config.flavor, 'f');
      expect(config.dartDefines, <String>['X=1']);
      expect(splitArgs(config.extraArgs), <String>[
        '--a',
        'two words',
        'q"uote',
        '',
        r'back\slash',
      ]);
    });

    test('a flag without a value stays in the extra args', () {
      final config = readOne('"args": ["--verbose", "--flavor"]');
      expect(config.flavor, isNull);
      expect(splitArgs(config.extraArgs), <String>['--verbose', '--flavor']);
    });

    test('env is kept', () {
      final config = readOne('"env": {"A": "1", "B": "two words"}');
      expect(config.environment, <String, String>{'A': '1', 'B': 'two words'});
    });

    test('preLaunchTask is flagged', () {
      expect(readOne('"preLaunchTask": "build"').hasPreLaunchTask, isTrue);
      expect(readOne('"name": "c"').hasPreLaunchTask, isFalse);
    });

    test('invalid JSON is unreadable with the parser message', () {
      final result = parseLaunchConfigs('{"configurations": [', projectRoot: root);
      expect(result, isA<LaunchConfigsUnreadable>());
      expect((result as LaunchConfigsUnreadable).reason, isNotEmpty);
      expect(parseLaunchConfigs('[1, 2]', projectRoot: root), isA<LaunchConfigsUnreadable>());
      expect(
        parseLaunchConfigs('{"configurations": 3}', projectRoot: root),
        isA<LaunchConfigsUnreadable>(),
      );
    });
  });

  group('files', () {
    late Directory project;

    setUp(() => project = Directory.systemTemp.createTempSync('launch_config_reader'));
    tearDown(() => project.deleteSync(recursive: true));

    test('launchJsonPath is .vscode/launch.json in the project', () {
      expect(launchJsonPath(root), '$root/.vscode/launch.json');
    });

    test('no file is missing', () async {
      expect(await readLaunchConfigs(project.path), isA<LaunchConfigsMissing>());
    });

    test('readLaunchConfigs reads the file of the project', () async {
      Directory('${project.path}/.vscode').createSync();
      File(launchJsonPath(project.path))
          .writeAsStringSync(single(r'"cwd": "${workspaceFolder}", "args": ["--flavor=x"],'));
      final result = await readLaunchConfigs(project.path);
      expect((result as LaunchConfigsRead).configs.single.flavor, 'x');
    });

    test('a file that is not JSON is unreadable', () async {
      Directory('${project.path}/.vscode').createSync();
      File(launchJsonPath(project.path)).writeAsStringSync('not json');
      expect(await readLaunchConfigs(project.path), isA<LaunchConfigsUnreadable>());
    });

    test('createLaunchJson writes the empty file and never overwrites', () async {
      await createLaunchJson(project.path);
      final file = File(launchJsonPath(project.path));
      expect(file.readAsStringSync(), '{"version": "0.2.0", "configurations": []}\n');
      expect(await readLaunchConfigs(project.path), isA<LaunchConfigsRead>());

      file.writeAsStringSync('mine');
      await createLaunchJson(project.path);
      expect(file.readAsStringSync(), 'mine');
    });
  });
}
