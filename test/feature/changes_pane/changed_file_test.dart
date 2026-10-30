import 'package:flutter_code_agent/src/feature/changes_pane/models/changed_file.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/turn_files/models/file_change_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TurnFilesItem turn(int seq, Map<String, String> files, {String? root}) => TurnFilesItem(
    seq,
    root: root,
    files: <TurnFile>[
      for (final MapEntry(:key, :value) in files.entries) TurnFile(path: key, status: value),
    ],
  );

  ToolCallItem edit(int seq, String path, {String? before, String after = 'new\n'}) => ToolCallItem(
    seq,
    toolCallId: 'call-$seq',
    title: 'Edit',
    kind: 'edit',
    content: <ToolContent>[ToolDiffContent(path: path, oldText: before, newText: after)],
  );

  List<String> paths(List<ChangedFile> files) => <String>[for (final f in files) f.path];

  test('changes merge turn files and agent diffs', () {
    final files = collectChanges(<ChatItem>[
      edit(1, '/p/lib/a.dart', before: 'old\n'),
      turn(2, <String, String>{'lib/a.dart': ' M'}, root: '/p'),
    ], projectRoot: '/p');

    expect(files, hasLength(1));
    expect(files.single.path, '/p/lib/a.dart');
    expect(files.single.status, 'modified');
    expect(files.single.diffs, hasLength(1));
  });

  test('a file with only agent diffs is edited and keeps its diffs in order', () {
    final files = collectChanges(<ChatItem>[
      edit(1, '/p/lib/a.dart', before: 'a\n', after: 'b\n'),
      edit(2, '/p/lib/a.dart', before: 'b\n', after: 'c\n'),
    ], projectRoot: '/p');

    expect(files.single.status, 'edited');
    expect(<String?>[for (final d in files.single.diffs) d.newText], <String>['b\n', 'c\n']);
  });

  test('a file changed only by a command has no diffs', () {
    final files = collectChanges(<ChatItem>[
      turn(1, <String, String>{'pubspec.lock': ' M', 'new.txt': '??'}, root: '/p'),
    ], projectRoot: '/p');

    expect(<String>[for (final f in files) f.status], containsAll(<String>['modified', 'added']));
    expect(files.every((f) => f.diffs.isEmpty), isTrue);
  });

  test('a project inside a git repo resolves paths against the git root', () {
    final files = collectChanges(<ChatItem>[
      turn(1, <String, String>{'app/lib/a.dart': ' M'}, root: '/repo'),
    ], projectRoot: '/repo/app');

    expect(paths(files), <String>['/repo/app/lib/a.dart']);
  });

  test('old journals without root fall back to the project root', () {
    final files = collectChanges(<ChatItem>[
      turn(1, <String, String>{'lib/a.dart': ' M'}),
    ], projectRoot: '/p');

    expect(paths(files), <String>['/p/lib/a.dart']);
  });

  test('a file reverted later is not listed', () {
    final files = collectChanges(<ChatItem>[
      edit(1, '/p/lib/a.dart', before: 'a\n'),
      turn(2, <String, String>{'lib/a.dart': ' M'}, root: '/p'),
      turn(3, <String, String>{'lib/a.dart': 'clean'}, root: '/p'),
    ], projectRoot: '/p');

    expect(files, isEmpty);
  });

  test('the last status wins', () {
    final files = collectChanges(<ChatItem>[
      turn(1, <String, String>{'a.txt': '??'}, root: '/p'),
      turn(2, <String, String>{'a.txt': ' D'}, root: '/p'),
    ], projectRoot: '/p');

    expect(files.single.status, 'deleted');
  });

  test('the most recently changed file comes first', () {
    final files = collectChanges(<ChatItem>[
      turn(1, <String, String>{'a.txt': ' M', 'b.txt': ' M'}, root: '/p'),
      edit(2, '/p/a.txt', before: 'x\n'),
      edit(3, '/p/c.txt', before: 'x\n'),
    ], projectRoot: '/p');

    expect(paths(files), <String>['/p/c.txt', '/p/a.txt', '/p/b.txt']);
  });

  test('paths with dots are normalized before merging', () {
    final files = collectChanges(<ChatItem>[
      edit(1, '/p/lib/../lib/a.dart', before: 'a\n'),
      turn(2, <String, String>{'lib/a.dart': ' M'}, root: '/p'),
    ], projectRoot: '/p');

    expect(paths(files), <String>['/p/lib/a.dart']);
  });

  test('other feed items are ignored', () {
    expect(
      collectChanges(<ChatItem>[
        const UserMessageItem(1, text: 'hi'),
        const SystemItem(2, type: 'error'),
      ], projectRoot: '/p'),
      isEmpty,
    );
  });

  group('fileChangeKind', () {
    test('maps git codes', () {
      expect(fileChangeKind('clean'), FileChangeKind.clean);
      expect(fileChangeKind('??'), FileChangeKind.added);
      expect(fileChangeKind('A '), FileChangeKind.added);
      expect(fileChangeKind(' D'), FileChangeKind.deleted);
      expect(fileChangeKind('R '), FileChangeKind.renamed);
      expect(fileChangeKind(' M'), FileChangeKind.modified);
      expect(fileChangeKind(''), FileChangeKind.modified);
    });
  });
}
