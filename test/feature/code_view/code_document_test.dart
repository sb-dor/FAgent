import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/code_document.dart';
import 'package:flutter_code_agent/src/feature/code_view/data/code_files_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../../support/memory_code_files_repository.dart';

void main() {
  const path = '/work/app/lib/main.dart';
  late MemoryCodeFilesRepository files;

  setUp(() => files = MemoryCodeFilesRepository(files: <String, String>{path: 'one\ntwo\n'}));

  /// Types [text] at the caret, as the editor does.
  void type(CodeDocument document, String text) => document.editing.replaceSelection(text);

  group('open', () {
    test('a text file is text and clean', () async {
      final document = await CodeDocument.open(path, files: files);
      addTearDown(document.dispose);

      expect(document.kind, CodeDocumentKind.text);
      expect(document.editing.text, 'one\ntwo\n');
      expect(document.dirty, isFalse);
      expect(document.stamp, files.stamps[path]);
    });

    test('an image is kind image, a binary notText, a 6 MB file tooLarge', () async {
      files
        ..put('/work/app/logo.PNG', '', notify: false)
        ..put('/work/app/a.bin', '', notify: false)
        ..put('/work/app/big.json', '', notify: false);
      files.notText.add('/work/app/a.bin');
      files.tooLarge.add('/work/app/big.json');

      final kinds = <CodeDocumentKind>[
        for (final file in <String>['/work/app/logo.PNG', '/work/app/a.bin', '/work/app/big.json'])
          (await CodeDocument.open(file, files: files)).kind,
      ];

      expect(kinds, <CodeDocumentKind>[
        CodeDocumentKind.image,
        CodeDocumentKind.notText,
        CodeDocumentKind.tooLarge,
      ]);
    });

    test('a missing file throws', () async {
      await expectLater(
        CodeDocument.open('/work/app/none.dart', files: files),
        throwsA(isA<io.PathNotFoundException>()),
      );
    });

    test('an unreadable file is unreadable with the error and cannot be saved', () async {
      final unreadable = _UnreadableFiles();

      final document = await CodeDocument.open(path, files: unreadable);
      await document.save();

      expect(document.kind, CodeDocumentKind.unreadable);
      expect(document.error, contains('Permission denied'));
      expect(unreadable.writes, 0);
    });
  });

  group('the bytes', () {
    late io.Directory root;
    late CodeFilesRepositoryImpl disk;

    setUp(() {
      root = io.Directory.systemTemp.createTempSync('code_document_');
      disk = CodeFilesRepositoryImpl(
        environment: const ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'}),
      );
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('save with no edits writes nothing', () async {
      final file = io.File(p.join(root.path, 'a.txt'))..writeAsStringSync('mixed\nends\r\n');
      final before = file.statSync().modified;

      final document = await CodeDocument.open(file.path, files: disk);
      await document.save();

      expect(file.readAsStringSync(), 'mixed\nends\r\n');
      expect(file.statSync().modified, before);
    });

    for (final (name, text) in <(String, String)>[
      ('LF', 'one\ntwo\n'),
      ('CRLF', 'one\r\ntwo\r\n'),
      ('no trailing newline', 'one\ntwo'),
      ('emoji and Cyrillic', 'привет 👋\nмир 🌍'),
    ]) {
      test('an edit keeps every other byte: $name', () async {
        final file = io.File(p.join(root.path, 'a.txt'))..writeAsStringSync(text);

        final document = await CodeDocument.open(file.path, files: disk);
        type(document, 'x');
        await document.save();

        expect(file.readAsStringSync(), 'x$text');
      });
    }

    test('a CRLF file keeps CRLF on a new line', () async {
      final file = io.File(p.join(root.path, 'a.txt'))..writeAsStringSync('one\r\ntwo\r\n');

      final document = await CodeDocument.open(file.path, files: disk);
      document.editing.selection = const CodeLineSelection.collapsed(index: 0, offset: 3);
      document.editing.applyNewLine();
      await document.save();

      expect(file.readAsStringSync(), 'one\r\n\r\ntwo\r\n');
    });
  });

  group('dirty', () {
    test('an edit is dirty, undo back clears it', () async {
      final document = await CodeDocument.open(path, files: files);
      var notified = 0;
      document.addListener(() => notified++);

      type(document, 'x');
      expect(document.dirty, isTrue);
      expect(notified, greaterThan(0));

      document.editing.undo();
      expect(document.dirty, isFalse);
    });

    test('moving the caret is not an edit', () async {
      final document = await CodeDocument.open(path, files: files);

      document.editing.selection = const CodeLineSelection.collapsed(index: 1, offset: 1);

      expect(document.dirty, isFalse);
    });
  });

  group('save', () {
    test('writes and records the new stamp', () async {
      final document = await CodeDocument.open(path, files: files);
      type(document, 'x');

      await document.save();

      expect(files.files[path], 'xone\ntwo\n');
      expect(document.dirty, isFalse);
      expect(document.stamp, files.stamps[path]);
    });

    test('a stale save throws FileChangedOnDiskException, overwrite writes', () async {
      final document = await CodeDocument.open(path, files: files);
      type(document, 'mine ');
      files.put(path, 'theirs\n', notify: false);

      await expectLater(document.save(), throwsA(isA<FileChangedOnDiskException>()));
      expect(files.files[path], 'theirs\n');
      expect(document.dirty, isTrue);

      await document.save(overwrite: true);
      expect(files.files[path], 'mine one\ntwo\n');
      expect(document.dirty, isFalse);
    });

    test('a write error sets error and stays dirty', () async {
      final document = await CodeDocument.open(path, files: files);
      type(document, 'x');
      files.writeError = const io.FileSystemException('Permission denied', path);

      await document.save();

      expect(document.error, contains('Permission denied'));
      expect(document.dirty, isTrue);

      await document.save();
      expect(document.error, isNull);
      expect(document.dirty, isFalse);
    });
  });

  group('the disk', () {
    test('a clean document reloads on an outside change and keeps the caret', () async {
      final document = await CodeDocument.open(path, files: files);
      document.editing.selection = const CodeLineSelection.collapsed(index: 1, offset: 2);
      files.put(path, 'one\ntwo\nthree\n', notify: false);

      await document.onDiskChange(FileChangeKind.modified);

      expect(document.editing.text, 'one\ntwo\nthree\n');
      expect(document.editing.selection, const CodeLineSelection.collapsed(index: 1, offset: 2));
      expect(document.dirty, isFalse);
      expect(document.changedOnDisk, isFalse);
    });

    test('a dirty document gets changedOnDisk, reloadFromDisk takes theirs', () async {
      final document = await CodeDocument.open(path, files: files);
      type(document, 'mine ');
      files.put(path, 'theirs\n', notify: false);

      await document.onDiskChange(FileChangeKind.modified);
      expect(document.changedOnDisk, isTrue);
      expect(document.editing.text, 'mine one\ntwo\n');

      await document.reloadFromDisk();
      expect(document.editing.text, 'theirs\n');
      expect(document.dirty, isFalse);
      expect(document.changedOnDisk, isFalse);
    });

    test('keepMine then save overwrites', () async {
      final document = await CodeDocument.open(path, files: files);
      type(document, 'mine ');
      files.put(path, 'theirs\n', notify: false);
      await document.onDiskChange(FileChangeKind.modified);

      document.keepMine();
      await document.save();

      expect(document.changedOnDisk, isFalse);
      expect(files.files[path], 'mine one\ntwo\n');
    });

    test("the app's own save does not mark changedOnDisk", () async {
      final document = await CodeDocument.open(path, files: files);
      type(document, 'x');
      await document.save();
      type(document, 'y');

      await document.onDiskChange(FileChangeKind.modified);

      expect(document.changedOnDisk, isFalse);
      expect(document.editing.text, 'xyone\ntwo\n');
    });

    test('an outside write right after a save is noticed', () async {
      final document = await CodeDocument.open(path, files: files);
      type(document, 'x');
      await document.save();
      files.put(path, 'agent\n', notify: false);

      await document.onDiskChange(FileChangeKind.modified);

      expect(document.editing.text, 'agent\n');
    });

    test('a change during a save is checked after it', () async {
      final slow = _SlowFiles(files);
      final document = await CodeDocument.open(path, files: slow);
      type(document, 'x');

      final saving = document.save();
      await document.onDiskChange(FileChangeKind.modified);
      await saving;

      expect(document.changedOnDisk, isFalse);
      expect(document.dirty, isFalse);
    });

    test('a deleted file is marked, keeps its text, and save recreates it', () async {
      final document = await CodeDocument.open(path, files: files);
      files.remove(path, notify: false);

      await document.onDiskChange(FileChangeKind.deleted);
      expect(document.deleted, isTrue);
      expect(document.editing.text, 'one\ntwo\n');

      await document.save();
      expect(document.deleted, isFalse);
      expect(files.files[path], 'one\ntwo\n');
    });

    test('a deleted file that comes back clean reloads', () async {
      final document = await CodeDocument.open(path, files: files);
      files.remove(path, notify: false);
      await document.onDiskChange(FileChangeKind.deleted);
      files.put(path, 'back\n', notify: false);

      await document.onDiskChange(FileChangeKind.created);

      expect(document.deleted, isFalse);
      expect(document.editing.text, 'back\n');
    });
  });
}

/// Files whose every read fails like a file without read permission.
final class _UnreadableFiles implements ICodeFilesRepository {
  final MemoryCodeFilesRepository _files = MemoryCodeFilesRepository();
  int writes = 0;

  @override
  Future<List<FileNode>> list(String root, String dir) => _files.list(root, dir);

  @override
  Stream<FileChange> watch(String root) => _files.watch(root);

  @override
  Future<FileContent> read(String path) async => throw io.FileSystemException(
    'Cannot open file',
    path,
    const io.OSError('Permission denied', 13),
  );

  @override
  Future<FileStamp?> stamp(String path) async => null;

  @override
  Future<FileStamp> write(String path, String text, {required FileStamp? expected}) {
    writes++;
    return _files.write(path, text, expected: expected);
  }
}

/// [MemoryCodeFilesRepository] whose writes wait a little, so a change can arrive during one.
final class _SlowFiles implements ICodeFilesRepository {
  _SlowFiles(this._files);

  final MemoryCodeFilesRepository _files;

  @override
  Future<List<FileNode>> list(String root, String dir) => _files.list(root, dir);

  @override
  Stream<FileChange> watch(String root) => _files.watch(root);

  @override
  Future<FileContent> read(String path) => _files.read(path);

  @override
  Future<FileStamp?> stamp(String path) => _files.stamp(path);

  @override
  Future<FileStamp> write(String path, String text, {required FileStamp? expected}) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return _files.write(path, text, expected: expected);
  }
}
