import 'dart:async';

import 'package:flutter_code_agent/src/feature/code_view/controller/file_tree_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_code_files_repository.dart';

void main() {
  const root = '/work/app';
  late MemoryCodeFilesRepository files;
  late StreamController<FileChange> changes;
  late FileTreeController tree;

  setUp(() {
    files = MemoryCodeFilesRepository(
      files: <String, String>{
        '$root/pubspec.yaml': 'name: app',
        '$root/lib/main.dart': 'void main() {}',
        '$root/lib/src/app.dart': 'class App {}',
      },
      folders: <String>{'$root/assets'},
      ignored: <String>{'$root/assets'},
    );
    changes = StreamController<FileChange>.broadcast();
    tree = FileTreeController(files: files, root: root, changes: changes.stream);
  });

  tearDown(() async {
    tree.dispose();
    await changes.close();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Each visible row as `<indent><name>[/]`, `+` for an expanded folder.
  List<String> rows() => switch (tree.state) {
    FileTree$LoadedState(:final rows) => <String>[
      for (final row in rows)
        '${'  ' * row.depth}${row.expanded ? '+' : ''}${row.node.name}${row.node.isDirectory ? '/' : ''}',
    ],
    _ => const <String>[],
  };

  test('load lists the root', () async {
    expect(tree.state, isA<FileTree$LoadingState>());

    tree.load();
    await settle();

    expect(rows(), <String>['assets/', 'lib/', 'pubspec.yaml']);
    final loaded = tree.state as FileTree$LoadedState;
    expect(loaded.rows.first.node.ignored, isTrue);
  });

  test('toggle expands and collapses with children at depth + 1', () async {
    tree.load();
    await settle();

    tree.toggle('$root/lib');
    await settle();
    expect(rows(), <String>['assets/', '+lib/', '  src/', '  main.dart', 'pubspec.yaml']);

    tree.toggle('$root/lib/src');
    await settle();
    expect(rows(), <String>[
      'assets/',
      '+lib/',
      '  +src/',
      '    app.dart',
      '  main.dart',
      'pubspec.yaml',
    ]);

    tree.toggle('$root/lib');
    await settle();
    expect(rows(), <String>['assets/', 'lib/', 'pubspec.yaml']);
  });

  test('reveal expands the ancestors', () async {
    tree.load();
    await settle();

    tree.reveal('$root/lib/src/app.dart');
    await settle();

    expect(rows(), <String>[
      'assets/',
      '+lib/',
      '  +src/',
      '    app.dart',
      '  main.dart',
      'pubspec.yaml',
    ]);
  });

  test('reveal of a path outside the root changes nothing', () async {
    tree.load();
    await settle();

    tree.reveal('/elsewhere/a.dart');
    await settle();

    expect(rows(), <String>['assets/', 'lib/', 'pubspec.yaml']);
  });

  test('a created file in an expanded folder appears', () async {
    tree.load();
    await settle();
    tree.toggle('$root/lib');
    await settle();

    files.put('$root/lib/b.dart', '', notify: false);
    changes.add(const FileChange(path: '$root/lib/b.dart', kind: FileChangeKind.created));
    await settle();

    expect(rows(), contains('  b.dart'));
  });

  test('a created file in the root appears', () async {
    tree.load();
    await settle();

    files.put('$root/README.md', '', notify: false);
    changes.add(const FileChange(path: '$root/README.md', kind: FileChangeKind.created));
    await settle();

    expect(rows(), <String>['assets/', 'lib/', 'pubspec.yaml', 'README.md']);
  });

  test('a change in a collapsed folder lists nothing', () async {
    tree.load();
    await settle();
    files.listed.clear();

    changes.add(const FileChange(path: '$root/lib/b.dart', kind: FileChangeKind.created));
    await settle();

    expect(files.listed, isEmpty);
  });

  test('deleting an expanded folder drops its rows', () async {
    tree.load();
    await settle();
    tree.reveal('$root/lib/src/app.dart');
    await settle();

    files.remove('$root/lib/src', notify: false);
    changes.add(const FileChange(path: '$root/lib/src', kind: FileChangeKind.deleted));
    await settle();

    expect(rows(), <String>['assets/', '+lib/', '  main.dart', 'pubspec.yaml']);
    // A folder made again under the same name starts collapsed.
    files.put('$root/lib/src/new.dart', '', notify: false);
    changes.add(const FileChange(path: '$root/lib/src', kind: FileChangeKind.created));
    await settle();
    expect(rows(), <String>['assets/', '+lib/', '  src/', '  main.dart', 'pubspec.yaml']);
  });

  test('a missing root is missing', () async {
    final missing = FileTreeController(files: files, root: '/nowhere', changes: changes.stream);
    addTearDown(missing.dispose);

    missing.load();
    await settle();

    expect(missing.state, isA<FileTree$MissingState>());
  });

  test('dispose cancels the changes subscription', () async {
    final own = StreamController<FileChange>();
    final controller = FileTreeController(files: files, root: root, changes: own.stream)..load();
    await settle();
    expect(own.hasListener, isTrue);

    controller.dispose();

    expect(own.hasListener, isFalse);
    await own.close();
  });
}
