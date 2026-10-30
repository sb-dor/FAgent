import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase database;
  late List<(String, List<String>)> runs;
  late Directory folder;
  late ProjectsRepositoryImpl repository;
  var exitCode = 0;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    runs = <(String, List<String>)>[];
    exitCode = 0;
    folder = Directory.systemTemp.createTempSync('open_path');
    const environment = ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'});
    repository = ProjectsRepositoryImpl(
      database: database,
      hub: AgentHub(database: database, environment: environment),
      runProcess: (executable, arguments) async {
        runs.add((executable, arguments));
        return ProcessResult(0, exitCode, '', 'failed');
      },
    );
  });

  tearDown(() async {
    folder.deleteSync(recursive: true);
    await database.close();
  });

  test('a file opens in the default text editor, never run', () async {
    final file = File(p.join(folder.path, 'a.dart'))..writeAsStringSync('x');

    await repository.openPath(file.path);

    expect(runs, hasLength(1));
    expect(runs.single.$1, 'open');
    expect(runs.single.$2, <String>['-t', file.path]);
  });

  test('a relative path is refused without running a process', () async {
    await expectLater(repository.openPath('lib/a.dart'), throwsA(isA<OpenPathRefusedException>()));
    expect(runs, isEmpty);
  });

  test('a missing file is refused without running a process', () async {
    await expectLater(
      repository.openPath(p.join(folder.path, 'missing.dart')),
      throwsA(isA<OpenPathRefusedException>()),
    );
    expect(runs, isEmpty);
  });

  test('a failing open throws', () async {
    final file = File(p.join(folder.path, 'a.dart'))..writeAsStringSync('x');
    exitCode = 1;

    await expectLater(repository.openPath(file.path), throwsA(isA<ProcessException>()));
  });
}
