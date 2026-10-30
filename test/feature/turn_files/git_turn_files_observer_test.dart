import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_event_store.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/turn_files/data/git_turn_files_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory repo;
  late GitTurnFilesObserver observer;

  setUpAll(() async {
    observer = GitTurnFilesObserver(environment: await ShellEnvironment.resolve());
  });

  void git(List<String> arguments) {
    final result = Process.runSync('git', <String>['-C', repo.path, ...arguments]);
    if (result.exitCode != 0) fail('git ${arguments.join(' ')}: ${result.stderr}');
  }

  void write(String path, String content) => File(p.join(repo.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  setUp(() {
    repo = Directory.systemTemp.createTempSync('turn_files_test');
    git(<String>['init', '-q']);
    git(<String>['config', 'user.email', 'test@example.com']);
    git(<String>['config', 'user.name', 'Test']);
    write('kept.txt', 'kept\n');
    write('dirty.txt', 'v1\n');
    write('old_name.txt', 'rename me\n');
    write('gone.txt', 'delete me\n');
    write('bin.dat', 'binary');
    git(<String>['add', '-A']);
    git(<String>['commit', '-qm', 'init']);
  });

  tearDown(() => repo.deleteSync(recursive: true));

  Future<Map<String, String>> changes(void Function() turn) async {
    final before = (await observer.snapshot(repo.path))!;
    turn();
    return <String, String>{
      for (final (path, status) in await observer.changedSince(before)) path: status,
    };
  }

  test('a file already dirty before the turn and edited again counts', () async {
    write('dirty.txt', 'v2\n');
    expect(await changes(() => write('dirty.txt', 'v3\n')), <String, String>{'dirty.txt': ' M'});
  });

  test('a dirty file the turn did not touch does not count', () async {
    write('dirty.txt', 'v2\n');
    expect(await changes(() => write('kept.txt', 'kept\nmore\n')), <String, String>{
      'kept.txt': ' M',
    });
  });

  test('untracked, renamed, deleted and binary files', () async {
    final changed = await changes(() {
      write('lib/new_file.dart', 'void main() {}\n');
      git(<String>['mv', 'old_name.txt', 'new_name.txt']);
      File(p.join(repo.path, 'gone.txt')).deleteSync();
      File(p.join(repo.path, 'bin.dat')).writeAsBytesSync(<int>[0, 1, 2, 255]);
    });
    expect(changed, <String, String>{
      'bin.dat': ' M',
      'gone.txt': ' D',
      'lib/new_file.dart': '??',
      'new_name.txt': 'R ',
    });
  });

  test('a file name with a newline stays one path', () async {
    expect(await changes(() => write('two\nlines.txt', 'x')), <String, String>{
      'two\nlines.txt': '??',
    });
  });

  test('a reverted change is reported as clean', () async {
    write('dirty.txt', 'v2\n');
    expect(await changes(() => git(<String>['checkout', '--', 'dirty.txt'])), <String, String>{
      'dirty.txt': 'clean',
    });
  });

  test(
    'a symlink pointing outside the project is not followed; its target change counts',
    () async {
      final outside = Directory.systemTemp.createTempSync('outside')..createTempSync();
      addTearDown(() => outside.deleteSync(recursive: true));
      final link = Link(p.join(repo.path, 'link'))..createSync(outside.path);
      final changed = await changes(() {
        // Content outside the project changes: not the project's change.
        File(p.join(outside.path, 'secret.txt')).writeAsStringSync('outside');
      });
      expect(
        changed,
        isEmpty,
        reason: 'the link is not followed, so content outside does not count',
      );

      final before = (await observer.snapshot(repo.path))!;
      link.updateSync('/tmp');
      expect((await observer.changedSince(before)).map((c) => c.$1), <String>['link']);
    },
  );

  test('a FIFO does not block the snapshot', () async {
    final fifo = p.join(repo.path, 'pipe');
    expect(Process.runSync('mkfifo', <String>[fifo]).exitCode, 0);
    final before = await observer.snapshot(repo.path).timeout(const Duration(seconds: 10));
    expect(before, isNotNull);
  });

  test('a folder outside git has no snapshot', () async {
    final plain = Directory.systemTemp.createTempSync('no_git');
    addTearDown(() => plain.deleteSync(recursive: true));
    expect(await observer.snapshot(plain.path), isNull);
  });

  test('parseStatus keeps the new path of a rename', () {
    expect(
      GitTurnFilesObserver.parseStatus('R  new.txt\u0000old.txt\u0000?? a b.txt\u0000'),
      <String, String>{'new.txt': 'R ', 'a b.txt': '??'},
    );
  });

  test('turn files carry the git root', () async {
    final before = (await observer.snapshot(repo.path))!;
    write('lib/a.dart', 'void main() {}\n');
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final session = LiveSession(
      id: 1,
      agentId: 'claude',
      cwd: repo.path,
      store: await SessionEventStore.open(database, 1),
    );

    final payload = await observer.afterTurn(session, before);

    expect(payload?['root'], before.root);
    expect(payload?['files'], <Object?>[
      <String, Object?>{'path': 'lib/a.dart', 'status': '??'},
    ]);
  });
}
