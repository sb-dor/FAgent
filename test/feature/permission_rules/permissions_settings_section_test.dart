import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart' show ProjectsTableCompanion;
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_permission_rules_repository.dart';
import '../../support/test_app.dart';

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _pageContent() => find.byKey(const ValueKey<String>('page-content'));

Finder _rule(int projectId, String rule) =>
    find.byKey(ValueKey<String>('permissions-rule-$projectId-$rule'));

Finder _remove(int projectId, String rule) =>
    find.byKey(ValueKey<String>('permissions-remove-$projectId-$rule'));

const _npmTest = 'Bash(npm test:*)';
const _pubDev = 'WebFetch(domain:pub.dev)';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;

  Future<int> addProject(WidgetTester tester, String name) => tester
      .runAsync(
        () => dependencies.database
            .into(dependencies.database.projectsTable)
            .insert(ProjectsTableCompanion.insert(path: '/work/$name', name: name)),
      )
      .then((value) => value!);

  /// Opens the Permissions section. The projects are named in [projects]; the first has the
  /// [_npmTest] and [_pubDev] rules unless [rules] says otherwise.
  Future<void> openSettings(
    WidgetTester tester, {
    required MemoryPermissionRulesRepository repository,
    Locale locale = const Locale('en'),
    bool dark = false,
    Size size = const Size(1280, 800),
    List<String> projects = const <String>['alpha', 'beta'],
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dependencies = testDependencies(permissionRulesRepository: repository);
    for (final name in projects) {
      await addProject(tester, name);
    }
    await tester.pumpWidget(
      testApp(
        const WorkspaceConfigWidget(),
        dependencies: dependencies,
        withSettings: true,
        locale: locale,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
      ),
    );
    await _settle(tester);
    await tester.pumpAndSettle();
    _workspace(tester).dataController.openView(WorkspaceView.settings, section: 'permissions');
    await tester.pump();
    await _settle(tester);
    await tester.pumpAndSettle();
  }

  MemoryPermissionRulesRepository twoProjects() => MemoryPermissionRulesRepository(
    rules: <String, List<String>>{
      '/work/alpha': <String>[_npmTest, _pubDev],
    },
  );

  testWidgets('shows the rules of a project and counts the projects without any', (tester) async {
    await openSettings(tester, repository: twoProjects());

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('/work/alpha'), findsOneWidget);
    expect(_rule(1, _npmTest), findsOneWidget);
    expect(_rule(1, _pubDev), findsOneWidget);
    expect(find.text('beta'), findsNothing);
    expect(find.text('No saved rules: 1 project'), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('remove asks the repository and the rule disappears', (tester) async {
    final repository = twoProjects();
    await openSettings(tester, repository: repository);

    await tester.tap(_remove(1, _npmTest));
    await tester.pump();
    await _settle(tester);

    expect(repository.removed, <String>['/work/alpha|$_npmTest']);
    expect(_rule(1, _npmTest), findsNothing);
    expect(_rule(1, _pubDev), findsOneWidget);

    await tester.tap(_remove(1, _pubDev));
    await tester.pump();
    await _settle(tester);

    // The project has no rules left, so it moves to the count.
    expect(find.text('alpha'), findsNothing);
    expect(find.text('No saved rules: 2 projects'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('refresh reads the files again', (tester) async {
    final repository = twoProjects();
    await openSettings(tester, repository: repository);
    expect(_rule(1, _pubDev), findsOneWidget);

    // Someone else removed a rule on disk.
    await repository.remove('/work/alpha', _pubDev);
    expect(_rule(1, _pubDev), findsOneWidget);

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    await _settle(tester);

    expect(_rule(1, _pubDev), findsNothing);
    expect(_rule(1, _npmTest), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('an unreadable project shows an error line', (tester) async {
    await openSettings(
      tester,
      repository: MemoryPermissionRulesRepository(unreadable: <String>{'/work/beta'}),
    );

    expect(find.text('beta'), findsOneWidget);
    expect(find.text('Could not read .claude/settings.local.json'), findsOneWidget);
    expect(find.text('No saved rules: 1 project'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('no projects shows an empty state', (tester) async {
    await openSettings(
      tester,
      repository: MemoryPermissionRulesRepository(),
      projects: const <String>[],
    );

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No projects yet'), findsOneWidget);
    expect(find.text('Refresh'), findsNothing);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('a project added later is read too', (tester) async {
    final repository = MemoryPermissionRulesRepository(
      rules: <String, List<String>>{
        '/work/gamma': <String>[_npmTest],
      },
    );
    await openSettings(tester, repository: repository, projects: const <String>[]);
    expect(find.byType(EmptyState), findsOneWidget);

    await addProject(tester, 'gamma');
    await _settle(tester);

    expect(find.byType(EmptyState), findsNothing);
    expect(find.text('gamma'), findsOneWidget);
    expect(_rule(1, _npmTest), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  testWidgets('russian plural of the projects without rules', (tester) async {
    final repository = MemoryPermissionRulesRepository(
      rules: <String, List<String>>{
        '/work/a': <String>[_npmTest],
      },
    );
    await openSettings(
      tester,
      repository: repository,
      locale: const Locale('ru'),
      projects: const <String>['a', 'b'],
    );
    expect(find.text('Без сохранённых правил: 1 проект'), findsOneWidget);
    expect(find.byTooltip('Удалить правило'), findsOneWidget);
    await disposeTestApp(tester, dependencies);
  });

  group('plural in Russian', () {
    for (final (count, text) in const <(int, String)>[(2, '2 проекта'), (5, '5 проектов')]) {
      testWidgets('$count projects', (tester) async {
        await openSettings(
          tester,
          repository: MemoryPermissionRulesRepository(),
          locale: const Locale('ru'),
          projects: <String>[for (var i = 0; i < count; i++) 'p$i'],
        );
        expect(find.text('Без сохранённых правил: $text'), findsOneWidget);
        await disposeTestApp(tester, dependencies);
      });
    }
  });

  group('layout', () {
    for (final size in const <Size>[Size(900, 600), Size(1280, 800)]) {
      for (final locale in const <Locale>[Locale('en'), Locale('ru')]) {
        for (final dark in const <bool>[false, true]) {
          testWidgets(
            'fits ${size.width.toInt()}×${size.height.toInt()} in ${locale.languageCode}, '
            '${dark ? 'dark' : 'light'}',
            (tester) async {
              await openSettings(
                tester,
                repository: MemoryPermissionRulesRepository(
                  rules: <String, List<String>>{
                    '/work/alpha': <String>[
                      _npmTest,
                      'Bash(${'flutter test --reporter expanded ' * 6}:*)',
                      'mcp__dart__hot_reload',
                    ],
                  },
                  unreadable: <String>{'/work/beta'},
                ),
                projects: const <String>['alpha', 'beta', 'gamma'],
                locale: locale,
                dark: dark,
                size: size,
              );
              expect(_pageContent(), findsOneWidget);
              expect(find.byType(IconButton), findsNWidgets(3));
              expect(
                find.text('Refresh'),
                locale.languageCode == 'en' ? findsOneWidget : findsNothing,
              );
              expect(tester.takeException(), isNull);
              await disposeTestApp(tester, dependencies);
            },
          );
        }
      }
    }
  });
}
