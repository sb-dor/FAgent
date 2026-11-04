import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_files_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const environment = ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'});
  final hasGit = io.Process.runSync('which', <String>['git']).exitCode == 0;

  late io.Directory root;
  late CodeFilesRepositoryImpl files;

  setUp(() {
    root = io.Directory.systemTemp.createTempSync('code_files_');
    // Watch events name the resolved path (`/private/var/…` on macOS).
    root = io.Directory(root.resolveSymbolicLinksSync());
    files = CodeFilesRepositoryImpl(environment: environment);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String path(String relative) => p.join(root.path, relative);

  void file(String relative, [String text = '']) =>
      (io.File(path(relative))..createSync(recursive: true)).writeAsStringSync(text);

  void folder(String relative) => io.Directory(path(relative)).createSync(recursive: true);

  void git(List<String> arguments) {
    final result = io.Process.runSync('git', <String>['-C', root.path, ...arguments]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }

  group('list', () {
    test('puts folders first and sorts by name', () async {
      file('b.dart');
      file('A.md');
      folder('zeta');
      folder('Alpha');

      final nodes = await files.list(root.path, root.path);

      expect(nodes.map((node) => node.name), <String>['Alpha', 'zeta', 'A.md', 'b.dart']);
      expect(nodes.first.isDirectory, isTrue);
      expect(nodes.last.path, path('b.dart'));
    });

    test('hides .git, .dart_tool and a build next to pubspec.yaml, but shows lib/build', () async {
      file('pubspec.yaml');
      folder('.git');
      folder('.dart_tool');
      folder('build');
      folder('lib/build');
      folder('lib/.dart_tool');

      final top = await files.list(root.path, root.path);
      final lib = await files.list(root.path, path('lib'));

      expect(top.map((node) => node.name), <String>['lib', 'pubspec.yaml']);
      expect(lib.map((node) => node.name), <String>['build']);
    });

    test('marks .gitignore\'d entries ignored', () async {
      file('.gitignore', 'secret.txt\nout/\n');
      file('secret.txt');
      file('main.dart');
      folder('out');
      git(<String>['init', '-q']);

      final nodes = await files.list(root.path, root.path);
      final ignored = {for (final node in nodes) node.name: node.ignored};

      expect(ignored, <String, bool>{
        'out': true,
        '.gitignore': false,
        'main.dart': false,
        'secret.txt': true,
      });
    }, skip: !hasGit);

    test('outside a git repository ignores nothing', () async {
      file('.gitignore', 'secret.txt\n');
      file('secret.txt');

      final nodes = await files.list(root.path, root.path);

      expect(nodes.every((node) => !node.ignored), isTrue);
    });
  });

  group('read', () {
    test('returns text and stamp', () async {
      file('a.dart', 'void main() {}\n');

      final content = await files.read(path('a.dart'));

      expect(content.text, 'void main() {}\n');
      expect(content.stamp, await files.stamp(path('a.dart')));
      expect(content.stamp.size, 15);
    });

    test('refuses a NUL byte in the first 8 KB', () async {
      io.File(path('a.bin')).writeAsBytesSync(<int>[0x41, 0x00, 0x42]);

      await expectLater(files.read(path('a.bin')), throwsA(isA<FileNotTextException>()));
    });

    test('refuses invalid UTF-8', () async {
      io.File(path('latin1.txt')).writeAsBytesSync(<int>[0x63, 0x61, 0x66, 0xE9]);

      await expectLater(files.read(path('latin1.txt')), throwsA(isA<FileNotTextException>()));
    });

    test('refuses a file over 5 MB', () async {
      io.File(path('big.txt')).writeAsStringSync('a' * (5 * 1024 * 1024 + 1));

      await expectLater(files.read(path('big.txt')), throwsA(isA<FileTooLargeException>()));
    });
  });

  group('write', () {
    test('with a stale stamp throws FileChangedOnDiskException and leaves the file', () async {
      file('a.dart', 'one');
      final read = await files.read(path('a.dart'));
      // Another writer, a moment later and longer.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      file('a.dart', 'theirs');

      await expectLater(
        files.write(path('a.dart'), 'mine', expected: read.stamp),
        throwsA(isA<FileChangedOnDiskException>()),
      );
      expect(io.File(path('a.dart')).readAsStringSync(), 'theirs');
    });

    test('with the current stamp writes and returns the new stamp', () async {
      file('a.dart', 'one');
      final read = await files.read(path('a.dart'));

      final stamp = await files.write(path('a.dart'), 'two!', expected: read.stamp);

      expect(io.File(path('a.dart')).readAsStringSync(), 'two!');
      expect(stamp, await files.stamp(path('a.dart')));
    });

    test('with expected: null recreates a deleted file', () async {
      file('a.dart', 'one');
      final read = await files.read(path('a.dart'));
      io.File(path('a.dart')).deleteSync();

      await expectLater(
        files.write(path('a.dart'), 'one', expected: read.stamp),
        throwsA(isA<FileChangedOnDiskException>()),
      );
      await files.write(path('a.dart'), 'one', expected: null);

      expect(io.File(path('a.dart')).readAsStringSync(), 'one');
    });

    test('keeps an executable mode', () async {
      file('gradlew', '#!/bin/sh\n');
      io.Process.runSync('chmod', <String>['755', path('gradlew')]);
      final read = await files.read(path('gradlew'));

      await files.write(path('gradlew'), '#!/bin/sh\necho hi\n', expected: read.stamp);

      expect(io.File(path('gradlew')).statSync().mode & 0x1FF, 0x1ED);
    });

    test('through a symlink updates the target and keeps the link', () async {
      file('real.dart', 'one');
      io.Link(path('link.dart')).createSync(path('real.dart'));
      final read = await files.read(path('link.dart'));

      await files.write(path('link.dart'), 'two', expected: read.stamp);

      expect(io.FileSystemEntity.isLinkSync(path('link.dart')), isTrue);
      expect(io.File(path('real.dart')).readAsStringSync(), 'two');
    });

    test('leaves no temp file behind', () async {
      file('a.dart', 'one');
      final read = await files.read(path('a.dart'));

      await files.write(path('a.dart'), 'two', expected: read.stamp);

      expect(root.listSync().map((entity) => p.basename(entity.path)), <String>['a.dart']);
    });
  });

  group('stamp', () {
    test('is null for a missing file', () async {
      expect(await files.stamp(path('nothing.dart')), isNull);
    });
  });

  group('watch', () {
    /// Collects the changes of [root] while [act] runs, then waits for the merge window.
    Future<List<FileChange>> watching(FutureOr<void> Function() act) async {
      final changes = <FileChange>[];
      final subscription = files.watch(root.path).listen(changes.add);
      // FSEvents needs a moment before it reports.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await act();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await subscription.cancel();
      return changes;
    }

    test('reports created, modified, deleted', () async {
      file('old.dart', 'x');
      file('gone.dart', 'x');

      final changes = await watching(() async {
        file('new.dart', 'x');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        io.File(path('old.dart')).writeAsStringSync('y', mode: io.FileMode.append);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        io.File(path('gone.dart')).deleteSync();
      });
      final kinds = {for (final change in changes) p.basename(change.path): change.kind};

      expect(kinds['new.dart'], FileChangeKind.created);
      // FSEvents may report a write to a recently created file as a create.
      expect(
        kinds['old.dart'],
        isIn(<FileChangeKind>[FileChangeKind.modified, FileChangeKind.created]),
      );
      expect(kinds['gone.dart'], FileChangeKind.deleted);
    });

    test('reports nothing for writes under build/ and .dart_tool/', () async {
      file('pubspec.yaml');
      folder('build');
      folder('.dart_tool');

      final changes = await watching(() {
        file('build/app.dill', 'x');
        file('.dart_tool/package_config.json', '{}');
      });

      // FSEvents may still report pubspec.yaml, written just before the watch started.
      final relative = changes.map((change) => p.relative(change.path, from: root.path));
      expect(
        relative.where((path) => path.startsWith('build') || path.startsWith('.dart_tool')),
        isEmpty,
      );
    });

    test('a replaced file is modified, not deleted', () async {
      file('a.dart', 'one');

      final changes = await watching(() {
        io.File(path('a.dart')).deleteSync();
        file('a.dart', 'two');
      });

      expect(
        changes.where((change) => p.basename(change.path) == 'a.dart').map((change) => change.kind),
        everyElement(isNot(FileChangeKind.deleted)),
      );
    });

    test('merges a burst of writes to one path into one change', () async {
      final changes = await watching(() {
        for (var i = 0; i < 5; i++) {
          file('a.dart', '$i');
        }
      });

      expect(changes.where((change) => p.basename(change.path) == 'a.dart'), hasLength(1));
    });
  });

  test('a FileStamp equals another with the same time and size', () {
    final at = DateTime(2026, 11, 4, 12);

    expect(FileStamp(modified: at, size: 3), FileStamp(modified: at, size: 3));
    expect(FileStamp(modified: at, size: 3), isNot(FileStamp(modified: at, size: 4)));
    expect(utf8.decode(utf8.encode('ok')), 'ok');
  });
}
