import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skill_list_tile.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_list.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_skills_repository.dart';
import '../../support/test_app.dart';

const String _averaRoot = '/work/avera-hotel';
const String _shopRoot = '/work/shop_app';

WorkspaceDataController _data(WidgetTester tester) =>
    WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget))).dataController;

SkillsConfigWidgetState _skills(WidgetTester tester) =>
    SkillsConfigInhWidget.of(tester.element(find.byType(SkillsList)));

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _navigation() => find.byKey(const ValueKey<String>('page-navigation'));

/// The tappable row of the navigation labelled [label].
Finder _navRow(String label) => find.ancestor(
  of: find.descendant(of: _navigation(), matching: find.text(label)),
  matching: find.byType(InkWell),
);

void _expectNavCount(String label, String count) {
  expect(_navRow(label), findsOneWidget, reason: label);
  expect(find.descendant(of: _navRow(label), matching: find.text(count)), findsOneWidget);
}

List<String> _listedNames(WidgetTester tester) => [
  for (final tile in tester.widgetList<SkillListTile>(find.byType(SkillListTile))) tile.item.name,
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late MemorySkillsRepository repository;
  late int averaId;
  late int shopId;

  MemorySkillsRepository seeded() => MemorySkillsRepository(
    items: [
      memorySkill('feature-architecture', description: 'New feature: config-widget'),
      memorySkill('avera-api-client', source: SkillSource.user, description: 'How to call the API'),
      memoryRule('dart-style', description: 'Always format'),
      memoryRule('team-rules', source: SkillSource.user),
    ],
    projectItems: {
      _averaRoot: [
        memorySkill('release-checklist', source: SkillSource.project, description: 'From the repo'),
        memoryRule('repo-rules', source: SkillSource.project),
      ],
      _shopRoot: [memorySkill('shop-deploy', source: SkillSource.project)],
    },
    texts: const {},
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    int projects = 2,
    Locale locale = const Locale('en'),
    ThemeData? theme,
    bool selectAvera = true,
  }) async {
    dependencies = testDependencies(skillsRepository: repository);
    await tester.runAsync(() async {
      final database = dependencies.database;
      if (projects > 0) {
        averaId = await database
            .into(database.projectsTable)
            .insert(ProjectsTableCompanion.insert(path: _averaRoot, name: 'avera-hotel'));
      }
      if (projects > 1) {
        shopId = await database
            .into(database.projectsTable)
            .insert(ProjectsTableCompanion.insert(path: _shopRoot, name: 'shop_app'));
      }
    });
    await tester.pumpWidget(
      testApp(
        const WorkspaceConfigWidget(),
        dependencies: dependencies,
        withSettings: true,
        locale: locale,
        theme: theme,
      ),
    );
    await _settle(tester);
    await tester.pumpAndSettle();
    if (projects > 0 && selectAvera) _data(tester).selectProject(averaId);
    _data(tester).openView(WorkspaceView.skills);
    await tester.pump();
    await _settle(tester);
    await tester.pump();
  }

  setUp(() => repository = seeded());

  Future<void> noOverflow(
    WidgetTester tester,
    Size size,
    Locale locale, {
    required bool dark,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository = MemorySkillsRepository(
      items: [
        memorySkill(
          'a-skill-with-a-really-long-name-that-goes-on-and-on-and-on',
          description: 'A very long description. ' * 12,
        ),
        memorySkill('short', source: SkillSource.user),
      ],
      projectItems: {
        _averaRoot: [memorySkill('release-checklist', source: SkillSource.project)],
      },
    );
    await pumpScreen(tester, locale: locale, theme: dark ? AppTheme.dark() : AppTheme.light());

    expect(find.byType(SkillListTile), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await disposeTestApp(tester, dependencies);
  }

  group('Skills screen', () {
    testWidgets('shows skills by source with counts', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      _expectNavCount('Skills', '3');
      _expectNavCount('Rules', '3');
      _expectNavCount('Built-in', '1');
      _expectNavCount('Mine', '1');
      _expectNavCount('Project (.claude/skills)', '1');
      expect(find.text('Sources'), findsOneWidget);
      expect(_listedNames(tester), [
        'feature-architecture',
        'avera-api-client',
        'release-checklist',
      ]);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('source filter and search', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await tester.tap(_navRow('Mine'));
      await tester.pump();
      expect(_listedNames(tester), ['avera-api-client']);

      // Tapping the chosen source again shows every source.
      await tester.tap(_navRow('Mine'));
      await tester.pump();
      expect(find.byType(SkillListTile), findsNWidgets(3));

      // The search looks at the description too and ignores case.
      await tester.enterText(find.byType(TextField), 'CONFIG-WIDGET');
      await tester.pump();
      expect(_listedNames(tester), ['feature-architecture']);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.byType(SkillListTile), findsNothing);
      expect(
        find.descendant(of: find.byType(SkillsList), matching: find.byType(EmptyState)),
        findsOneWidget,
      );
      expect(find.text('Nothing found'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the switch writes for the screen project', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(SkillListTile, 'feature-architecture'),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      await _settle(tester);

      expect(
        repository.calls,
        contains('setEnabled skill:builtin:feature-architecture false project=$averaId'),
      );
      final forProject = await tester.runAsync(
        () => repository.watch(projectId: averaId, projectRoot: _averaRoot).first,
      );
      final item = forProject!.byId('skill:builtin:feature-architecture')!;
      expect(item.enabled, isFalse);
      expect(item.enabledGlobally, isTrue);
      expect(item.exceptions, {averaId});
      final other = await tester.runAsync(
        () => repository.watch(projectId: shopId, projectRoot: _shopRoot).first,
      );
      expect(other!.byId('skill:builtin:feature-architecture')!.enabled, isTrue);
      // The row follows the library.
      final tile = tester.widget<Switch>(
        find.descendant(
          of: find.widgetWithText(SkillListTile, 'feature-architecture'),
          matching: find.byType(Switch),
        ),
      );
      expect(tile.value, isFalse);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('rules section lists rules', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await tester.tap(_navRow('Rules'));
      await tester.pump();
      expect(_listedNames(tester), ['dart-style', 'team-rules', 'repo-rules']);
      _expectNavCount('Built-in', '1');
      _expectNavCount('Mine', '1');
      _expectNavCount('Project (.claude/skills)', '1');

      // Back to the skills clears the source choice.
      await tester.tap(_navRow('Built-in'));
      await tester.pump();
      expect(_listedNames(tester), ['dart-style']);
      await tester.tap(_navRow('Skills'));
      await tester.pump();
      expect(find.byType(SkillListTile), findsNWidgets(3));
      expect(_skills(tester).view.source, isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('add source says M3', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await tester.tap(find.text('＋ Add source…'));
      await tester.pump();
      expect(find.text('Coming in M3'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('picking a row selects it; nothing is selected at first', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      expect(find.text('Pick a skill or a rule'), findsOneWidget);
      await tester.tap(find.text('avera-api-client'));
      await tester.pump();
      expect(_skills(tester).view.selectedId, 'skill:user:avera-api-client');
      expect(
        tester
            .widget<SkillListTile>(find.widgetWithText(SkillListTile, 'avera-api-client'))
            .selected,
        isTrue,
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the project selector changes the library and the project source', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      expect(find.text('Project: avera-hotel'), findsOneWidget);
      await tester.tap(find.text('Project: avera-hotel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('shop_app'));
      await tester.pump(const Duration(milliseconds: 200));
      await _settle(tester);

      expect(find.text('Project: shop_app'), findsOneWidget);
      expect(_skills(tester).view.projectId, shopId);
      expect(_listedNames(tester), ['feature-architecture', 'avera-api-client', 'shop-deploy']);
      expect(repository.calls.last, 'watch project=$shopId root=$_shopRoot');

      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      expect(
        repository.calls,
        contains('setEnabled skill:project:shop-deploy false project=$shopId'),
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the screen starts on the window project; openSkills overrides it', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      expect(_skills(tester).view.projectId, averaId);

      _data(tester)
        ..openView(WorkspaceView.chat)
        ..openSkills(itemId: 'rule:project:repo-rules', projectId: averaId);
      await tester.pump();
      await _settle(tester);
      expect(_skills(tester).view.kind, KnowledgeKind.rule);
      expect(_skills(tester).view.selectedId, 'rule:project:repo-rules');
      expect(_skills(tester).view.projectId, averaId);
      expect(
        tester.widget<SkillListTile>(find.widgetWithText(SkillListTile, 'repo-rules')).selected,
        isTrue,
      );

      _data(tester)
        ..openView(WorkspaceView.chat)
        ..openSkills(projectId: shopId);
      await tester.pump();
      await _settle(tester);
      expect(_skills(tester).view.projectId, shopId);
      expect(find.text('Project: shop_app'), findsOneWidget);
      expect(_data(tester).takeSkillsTarget(), isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('without projects the chip is hidden and the switch is global', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester, projects: 0);

      expect(find.textContaining('Project:'), findsNothing);
      expect(_navRow('Project (.claude/skills)'), findsNothing);
      expect(_listedNames(tester), ['feature-architecture', 'avera-api-client']);

      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(
        repository.calls,
        contains('setEnabled skill:builtin:feature-architecture false project=null'),
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('projects without a selected one: global switch, chip asks to choose', (
      tester,
    ) async {
      useDesktopView(tester);
      await pumpScreen(tester, selectAvera: false);

      expect(find.text('Choose a project'), findsOneWidget);
      expect(_navRow('Project (.claude/skills)'), findsNothing);
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      expect(
        repository.calls,
        contains('setEnabled skill:builtin:feature-architecture false project=null'),
      );
      await disposeTestApp(tester, dependencies);
    });

    for (final locale in const [Locale('en'), Locale('ru')]) {
      for (final dark in const [false, true]) {
        testWidgets(
          'no overflow at 900×600 in ${locale.languageCode}, ${dark ? 'dark' : 'light'}',
          (tester) => noOverflow(tester, const Size(900, 600), locale, dark: dark),
        );
      }
      testWidgets(
        'no overflow at 1280×800 in ${locale.languageCode} (full navigation)',
        (tester) => noOverflow(tester, const Size(1280, 800), locale, dark: false),
      );
    }
  });
}
