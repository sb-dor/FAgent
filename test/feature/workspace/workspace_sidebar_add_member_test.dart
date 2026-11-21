import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/add_member_dialog.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late Directory root;

  setUp(() {
    dependencies = testDependencies();
    root = Directory.systemTemp.createTempSync('add_member_sidebar');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  /// A folder under [root]: a pub workspace without `lib/` when [monorepo], an app otherwise.
  String makeProject(String name, {required bool monorepo}) {
    final dir = Directory('${root.path}/$name')..createSync();
    if (monorepo) {
      File('${dir.path}/pubspec.yaml')
          .writeAsStringSync('name: ${name}_workspace\nworkspace:\n  - apps/*\n  - packages/*\n');
    } else {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: $name\n');
      Directory('${dir.path}/lib').createSync();
    }
    return dir.path;
  }

  Future<void> pumpSidebar(
    WidgetTester tester,
    Map<String, bool> projects, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => disposeTestApp(tester, dependencies));
    final database = dependencies.database;
    await tester.runAsync(() async {
      for (final entry in projects.entries) {
        await database
            .into(database.projectsTable)
            .insert(
              ProjectsTableCompanion.insert(
                path: makeProject(entry.key, monorepo: entry.value),
                name: entry.key,
              ),
            );
      }
    });
    await tester.pumpWidget(
      testApp(
        const WorkspaceConfigWidget(),
        dependencies: dependencies,
        withSettings: true,
        locale: locale,
      ),
    );
    await _settle(tester);
    await tester.pumpAndSettle();
  }

  /// Opens the menu of the project in the [index]-th header (⋯ buttons are in sidebar order).
  Future<void> openMenu(WidgetTester tester, int index) async {
    await tester.tap(find.byIcon(Icons.more_horiz).at(index));
    await tester.pumpAndSettle();
  }

  testWidgets('menu offers Add to project only for a monorepo', (tester) async {
    await pumpSidebar(tester, <String, bool>{'plain_app': false});
    await openMenu(tester, 0);
    expect(find.text('Show in Finder'), findsOneWidget);
    expect(find.text('Add to project…'), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();

    // The project is replaced by a monorepo on disk: the menu looks again each time.
    File('${root.path}/plain_app/pubspec.yaml')
        .writeAsStringSync('name: plain_app_workspace\nworkspace:\n  - apps/*\n');
    Directory('${root.path}/plain_app/lib').deleteSync();
    await openMenu(tester, 0);
    expect(find.text('Add to project…'), findsOneWidget);
  });

  testWidgets('Add to project opens the dialog of that project', (tester) async {
    await pumpSidebar(tester, <String, bool>{'shop': true});
    await openMenu(tester, 0);

    await tester.tap(find.text('Add to project…'));
    await tester.pumpAndSettle();

    expect(find.byType(AddMemberDialog), findsOneWidget);
    expect(find.text('New project member'), findsOneWidget);
    expect(tester.widget<AddMemberDialog>(find.byType(AddMemberDialog)).project.name, 'shop');
  });

  testWidgets('the menu is in Russian too', (tester) async {
    await pumpSidebar(tester, <String, bool>{'shop': true}, locale: const Locale('ru'));
    await openMenu(tester, 0);

    expect(find.text('Добавить в проект…'), findsOneWidget);
  });
}
