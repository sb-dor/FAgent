import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/feature/code_view/controller/file_tree_controller.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_file.dart';
import 'package:flutter_code_agent/src/feature/code_view/widgets/code_explorer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_code_files_repository.dart';
import '../../support/test_app.dart';

void main() {
  const root = '/p';
  late MemoryCodeFilesRepository files;
  late StreamController<FileChange> changes;
  late FileTreeController tree;
  late List<String> opened;
  late List<String> external;

  setUp(() {
    files = MemoryCodeFilesRepository(
      files: <String, String>{'$root/lib/main.dart': '', '$root/pubspec.yaml': ''},
      folders: <String>{'$root/build_cache'},
      ignored: <String>{'$root/build_cache'},
    );
    changes = StreamController<FileChange>.broadcast();
    opened = <String>[];
    external = <String>[];
  });

  tearDown(() => changes.close());

  Future<void> pump(WidgetTester tester, {String path = root}) async {
    tree = FileTreeController(files: files, root: path, changes: changes.stream)..load();
    addTearDown(tree.dispose);
    await tester.pumpWidget(
      testApp(
        CodeExplorer(tree: tree, onOpenFile: opened.add, onOpenExternally: external.add),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the root entries', (tester) async {
    await pump(tester);

    expect(find.text('build_cache'), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('pubspec.yaml'), findsOneWidget);
  });

  testWidgets('clicking a folder expands it', (tester) async {
    await pump(tester);

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('clicking a file opens it', (tester) async {
    await pump(tester);

    await tester.tap(find.text('pubspec.yaml'));
    await tester.pumpAndSettle();

    expect(opened, <String>['$root/pubspec.yaml']);
  });

  testWidgets('an ignored entry is muted', (tester) async {
    await pump(tester);
    final colors = tester.element(find.text('build_cache')).colors;

    expect(tester.widget<Text>(find.text('build_cache')).style?.color, colors.muted);
    expect(tester.widget<Text>(find.text('lib')).style?.color, colors.text);
  });

  testWidgets('a missing root shows the line', (tester) async {
    await pump(tester, path: '/nowhere');

    expect(find.text('Project folder not found'), findsOneWidget);
  });

  testWidgets('the context menu opens externally', (tester) async {
    await pump(tester);

    await tester.tap(find.text('pubspec.yaml'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in default app'));
    await tester.pumpAndSettle();

    expect(external, <String>['$root/pubspec.yaml']);
    expect(opened, isEmpty);
  });
}
