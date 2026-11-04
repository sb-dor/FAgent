import 'package:flutter_code_agent/src/feature/code_view/controller/code_workspace.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/file_tree_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/memory_code_view_state_repository.dart';
import '../../support/memory_dart_analysis_repository.dart';

void main() {
  late MemoryCodeFilesRepository files;
  late CodeViewRegistry registry;
  late Map<String, MemoryDartAnalysisRepository> analyses;

  setUp(() {
    files = MemoryCodeFilesRepository(
      files: <String, String>{'/a/main.dart': 'a\n', '/b/main.dart': 'b\n'},
    );
    analyses = <String, MemoryDartAnalysisRepository>{};
    registry = CodeViewRegistry(
      files: files,
      state: MemoryCodeViewStateRepository(),
      analysisFor: (root) => analyses[root] = MemoryDartAnalysisRepository(),
    );
  });

  tearDown(() => registry.dispose());

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  test('workspaceFor keeps one workspace per project and loads its tree', () async {
    final first = registry.workspaceFor(projectId: 1, root: '/a');
    await settle();

    expect(registry.workspaceFor(projectId: 1, root: '/a'), same(first));
    expect(first.tree.state, isA<FileTree$LoadedState>());
    expect(files.watched, isTrue);
  });

  test('count per project and in all, and notifies when a document turns dirty', () async {
    final a = registry.workspaceFor(projectId: 1, root: '/a');
    final b = registry.workspaceFor(projectId: 2, root: '/b');
    var notified = 0;
    registry.addListener(() => notified++);

    (await a.tabs.open('/a/main.dart')).editing.replaceSelection('x');
    (await b.tabs.open('/b/main.dart')).editing.replaceSelection('y');

    expect(registry.count(projectId: 1), 1);
    expect(registry.count(), 2);
    expect(notified, greaterThan(0));
  });

  test('saveAll saves and returns true, a conflict returns false', () async {
    final a = registry.workspaceFor(projectId: 1, root: '/a');
    final b = registry.workspaceFor(projectId: 2, root: '/b');
    (await a.tabs.open('/a/main.dart')).editing.replaceSelection('x');
    (await b.tabs.open('/b/main.dart')).editing.replaceSelection('y');

    expect(await registry.saveAll(projectId: 1), isTrue);
    expect(registry.count(), 1);

    files.put('/b/main.dart', 'theirs\n', notify: false);
    expect(await registry.saveAll(), isFalse);
  });

  test('discard closes the project workspace and its watch', () async {
    final a = registry.workspaceFor(projectId: 1, root: '/a');
    (await a.tabs.open('/a/main.dart')).editing.replaceSelection('x');
    await settle();

    registry.discard(1);
    await settle();

    expect(registry.count(), 0);
    expect(files.watched, isFalse);
    expect(registry.workspaceFor(projectId: 1, root: '/a'), isNot(same(a)));
  });

  test('M10: a tab keeps its find and scroll state until it closes', () async {
    final a = registry.workspaceFor(projectId: 1, root: '/a');
    final document = await a.tabs.open('/a/main.dart');

    final view = a.viewOf(document);
    expect(a.viewOf(document), same(view));

    a.tabs.close(document.path);
    final again = await a.tabs.open('/a/main.dart');
    expect(a.viewOf(again), isNot(same(view)));
  });

  test('another root for the same project makes a new workspace', () async {
    final a = registry.workspaceFor(projectId: 1, root: '/a');

    expect(registry.workspaceFor(projectId: 1, root: '/b'), isNot(same(a)));
  });

  group('Dart analysis', () {
    test('opening, editing and closing a .dart tab drives open, change and close', () async {
      final a = registry.workspaceFor(projectId: 1, root: '/a');
      final document = await a.tabs.open('/a/main.dart');
      document.editing.replaceSelection('x');
      document.editing.selection = document.editing.selection;
      a.tabs.close('/a/main.dart', discard: true);

      expect(analyses['/a']!.calls, <(String, String, String?)>[
        ('open', '/a/main.dart', 'a\n'),
        ('change', '/a/main.dart', 'xa\n'),
        ('close', '/a/main.dart', null),
      ]);
    });

    test('a workspace disposes its analysis', () async {
      registry
        ..workspaceFor(projectId: 1, root: '/a')
        ..discard(1);
      await settle();

      expect(analyses['/a']!.disposed, isTrue);
    });

    test('close waits for every analysis to stop', () async {
      registry
        ..workspaceFor(projectId: 1, root: '/a')
        ..workspaceFor(projectId: 2, root: '/b');

      await registry.close();

      expect(analyses.values.every((analysis) => analysis.disposed), isTrue);
    });
  });
}
