import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/src/feature/code_view/controller/code_tabs_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_view_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/memory_code_view_state_repository.dart';

void main() {
  const root = '/work/app';
  const main = '$root/lib/main.dart';
  const pubspec = '$root/pubspec.yaml';
  late MemoryCodeFilesRepository files;
  late MemoryCodeViewStateRepository state;
  late StreamController<FileChange> changes;

  setUp(() {
    files = MemoryCodeFilesRepository(
      files: <String, String>{main: 'a\nb\nc\nd\n', pubspec: 'name: app\n'},
    );
    state = MemoryCodeViewStateRepository();
    changes = StreamController<FileChange>.broadcast();
  });

  tearDown(() => changes.close());

  CodeTabsController create() {
    final tabs = CodeTabsController(
      projectId: 1,
      root: root,
      files: files,
      state: state,
      changes: changes.stream,
    );
    addTearDown(tabs.dispose);
    return tabs;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('open adds a tab and activates it', () async {
    final tabs = create();

    await tabs.open(main);
    await tabs.open(pubspec);

    expect(tabs.tabs.map((tab) => tab.path), <String>[main, pubspec]);
    expect(tabs.active?.path, pubspec);
  });

  test('open reuses the tab and moves the caret to the line', () async {
    final tabs = create();
    await tabs.open(main);
    await tabs.open(pubspec);

    final document = await tabs.open(main, line: 3);

    expect(tabs.tabs, hasLength(2));
    expect(tabs.active, same(document));
    expect(document.editing.selection, const CodeLineSelection.collapsed(index: 2, offset: 0));
  });

  test('a line past the end goes to the last line', () async {
    final tabs = create();

    final document = await tabs.open(main, line: 99);

    expect(document.editing.selection.extentIndex, document.editing.lineCount - 1);
  });

  test('close refuses a dirty tab unless discard', () async {
    final tabs = create();
    final document = await tabs.open(main);
    document.editing.replaceSelection('x');

    expect(tabs.close(main), isFalse);
    expect(tabs.tabs, hasLength(1));

    expect(tabs.close(main, discard: true), isTrue);
    expect(tabs.tabs, isEmpty);
    expect(tabs.active, isNull);
  });

  test('closing the active tab activates its neighbour', () async {
    final tabs = create();
    await tabs.open(main);
    await tabs.open(pubspec);
    tabs
      ..activate(main)
      ..close(main);

    expect(tabs.active?.path, pubspec);
  });

  test('an outside change reloads a clean tab and marks a dirty one', () async {
    final tabs = create();
    final clean = await tabs.open(main);
    final dirty = await tabs.open(pubspec);
    dirty.editing.replaceSelection('x');
    await settle();

    files
      ..put(main, 'agent\n', notify: false)
      ..put(pubspec, 'agent\n', notify: false);
    changes
      ..add(const FileChange(path: main, kind: FileChangeKind.modified))
      ..add(const FileChange(path: pubspec, kind: FileChangeKind.modified));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(clean.editing.text, 'agent\n');
    expect(dirty.changedOnDisk, isTrue);
  });

  test('a watch error keeps the tabs', () async {
    final tabs = create();
    await tabs.open(main);

    changes.addError(const FileSystemException('watch failed'));
    await settle();

    expect(tabs.tabs, hasLength(1));
  });

  test('deleting a folder marks the tabs under it deleted', () async {
    final tabs = create();
    final document = await tabs.open(main);
    files.remove('$root/lib', notify: false);

    changes.add(const FileChange(path: '$root/lib', kind: FileChangeKind.deleted));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(document.deleted, isTrue);
  });

  test('unsavedCount and saveAll', () async {
    final tabs = create();
    (await tabs.open(main)).editing.replaceSelection('x');
    (await tabs.open(pubspec)).editing.replaceSelection('y');

    expect(tabs.unsavedCount, 2);
    expect(await tabs.saveAll(), isTrue);
    expect(tabs.unsavedCount, 0);
    expect(files.files[main], 'xa\nb\nc\nd\n');
  });

  test('saveAll returns false on a conflict and keeps that one unsaved', () async {
    final tabs = create();
    (await tabs.open(main)).editing.replaceSelection('x');
    files.put(main, 'theirs\n', notify: false);

    expect(await tabs.saveAll(), isFalse);
    expect(tabs.unsavedCount, 1);
  });

  test('mode, tabs, active and width are saved and restored', () async {
    final tabs = create();
    await tabs.restore();
    await tabs.open(main);
    await tabs.open(pubspec);
    tabs
      ..activate(main)
      ..setMode(CodeViewMode.code)
      ..setExplorerWidth(300);
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(
      state.states[1],
      const CodeViewState(
        mode: CodeViewMode.code,
        tabs: <String>['lib/main.dart', 'pubspec.yaml'],
        activeTab: 'lib/main.dart',
        explorerWidth: 300,
      ),
    );
    // One save for the burst of changes.
    expect(state.saves, hasLength(1));

    final again = create();
    await again.restore();

    expect(again.mode, CodeViewMode.code);
    expect(again.tabs.map((tab) => tab.path), <String>[main, pubspec]);
    expect(again.active?.path, main);
    expect(again.explorerWidth, 300);
  });

  test('a missing file is dropped on restore', () async {
    state.states[1] = const CodeViewState(
      tabs: <String>['lib/gone.dart', 'pubspec.yaml'],
      activeTab: 'lib/gone.dart',
    );
    final tabs = create();

    await tabs.restore();

    expect(tabs.tabs.map((tab) => tab.path), <String>[pubspec]);
    expect(tabs.active?.path, pubspec);
  });

  test('the explorer width is clamped', () {
    final tabs = create()..setExplorerWidth(50);
    expect(tabs.explorerWidth, 180);

    tabs.setExplorerWidth(900);
    expect(tabs.explorerWidth, 480);
  });

  test('a pending state is saved on dispose', () async {
    CodeTabsController(
      projectId: 1,
      root: root,
      files: files,
      state: state,
      changes: changes.stream,
    )
      ..setMode(CodeViewMode.code)
      ..dispose();
    await settle();

    expect(state.states[1]?.mode, CodeViewMode.code);
  });

  test('a document turning dirty notifies the tabs', () async {
    final tabs = create();
    final document = await tabs.open(main);
    var notified = 0;
    tabs.addListener(() => notified++);

    document.editing.replaceSelection('x');

    expect(notified, greaterThan(0));
  });
}
