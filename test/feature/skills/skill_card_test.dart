import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
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
const String _builtin = 'skill:builtin:feature-architecture';
const String _mine = 'skill:user:avera-api-client';
const String _generatePrompt =
    'Write a Claude Code skill for this project in .claude/skills/<name>/SKILL.md '
    '(frontmatter: name, description). The skill should: ';

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

WorkspaceDataController _data(WidgetTester tester) => _workspace(tester).dataController;

SkillsConfigWidgetState _skills(WidgetTester tester) =>
    SkillsConfigInhWidget.of(tester.element(find.byType(SkillsList)));

/// Lets drift's real-async work finish, then rebuilds.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _settleAll(WidgetTester tester, [int times = 3]) async {
  for (var i = 0; i < times; i++) {
    await _settle(tester);
  }
}

Finder _row(String name) => find.widgetWithText(SkillListTile, name);

Finder _globalSwitch() => find.byKey(const ValueKey<String>('skill-global-switch'));

Finder _projectSwitch() => find.byKey(const ValueKey<String>('skill-project-switch'));

Finder _editor() => find.byKey(const ValueKey<String>('skill-editor'));

String _editorText(WidgetTester tester) => tester.widget<TextField>(_editor()).controller!.text;

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(_button(label)).onPressed != null;

List<KnowledgeItem> _listed(WidgetTester tester, String name) => [
  for (final tile in tester.widgetList<SkillListTile>(find.byType(SkillListTile)))
    if (tile.item.name == name) tile.item,
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late MemorySkillsRepository repository;
  late int averaId;
  late int shopId;
  late int chatId;

  MemorySkillsRepository seeded() => MemorySkillsRepository(
    items: [
      memorySkill(
        'feature-architecture',
        description: 'New feature: config-widget',
      ).copyWith(version: '1.3'),
      memorySkill('avera-api-client', source: SkillSource.user, description: 'How to call the API'),
      memorySkill('other-skill', source: SkillSource.user),
      memorySkill(
        'broken',
        source: SkillSource.user,
      ).copyWith(problem: 'Cannot read the frontmatter'),
      memoryRule('dart-style', description: 'Always format'),
    ],
    projectItems: {
      _averaRoot: [memorySkill('c', source: SkillSource.project, description: 'From the repo')],
      _shopRoot: [memorySkill('shop-deploy', source: SkillSource.project)],
    },
    texts: const {
      _builtin: '---\nname: feature-architecture\nversion: 1.3\n---\n# Feature architecture\n',
      _mine: '---\nname: avera-api-client\n---\n# API\n',
      'skill:user:other-skill': '# other\n',
      'skill:user:broken': 'oops',
      'rule:builtin:dart-style': '# dart-style\n',
      'skill:project:c': '# c\n',
    },
    importable: const {'/imports/pretty': '---\nname: pretty\n---\n# pretty\n'},
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool selectProject = true,
    bool withChat = false,
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) async {
    dependencies = testDependencies(skillsRepository: repository);
    await tester.runAsync(() async {
      final database = dependencies.database;
      averaId = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: _averaRoot, name: 'avera-hotel'));
      shopId = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: _shopRoot, name: 'shop_app'));
      chatId = await database
          .into(database.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: averaId,
              agentId: 'claude',
              title: const Value<String>('A chat'),
            ),
          );
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
    if (selectProject) _data(tester).selectProject(averaId);
    if (withChat) _data(tester).selectSession(chatId);
    await tester.pump();
    await _settleAll(tester, withChat ? 5 : 1);
    _data(tester).openView(WorkspaceView.skills);
    await tester.pump();
    await _settleAll(tester);
  }

  Future<void> select(WidgetTester tester, String name) async {
    await tester.tap(_row(name));
    await tester.pump();
    await _settleAll(tester, 2);
  }

  Future<void> openAddMenu(WidgetTester tester) async {
    await tester.tap(find.text('＋ Add'));
    await tester.pumpAndSettle();
  }

  Future<void> submitName(WidgetTester tester, String name) async {
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      name,
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    await _settleAll(tester, 2);
  }

  Future<void> chooseAdd(WidgetTester tester, String item) async {
    await openAddMenu(tester);
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  setUp(() => repository = seeded());

  group('Skill card', () {
    testWidgets('nothing selected shows the hint', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      expect(find.text('Pick a skill or a rule'), findsOneWidget);
      expect(_editor(), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('built-in card is read-only and duplicates into Mine', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await select(tester, 'feature-architecture');

      expect(tester.widget<TextField>(_editor()).readOnly, isTrue);
      expect(_editorText(tester), contains('# Feature architecture'));
      expect(find.text('· v1.3'), findsOneWidget);
      expect(
        find.text('Built-in items are read-only. To change one, duplicate it.'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsNothing);
      expect(find.text('Duplicate to Mine'), findsOneWidget);

      await tester.tap(find.text('Duplicate to Mine'));
      await tester.pump();
      await _settleAll(tester);

      expect(_skills(tester).view.selectedId, 'skill:user:feature-architecture');
      expect(_listed(tester, 'feature-architecture').map((item) => item.source), [
        SkillSource.builtin,
        SkillSource.user,
      ]);
      expect(find.text('Duplicate to Mine'), findsNothing);
      expect(tester.widget<TextField>(_editor()).readOnly, isFalse);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('editing and saving a user skill', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      await select(tester, 'avera-api-client');

      expect(_editorText(tester), contains('# API'));
      expect(_enabled(tester, 'Save'), isFalse);

      await tester.enterText(_editor(), 'new text');
      await tester.pump();
      expect(_enabled(tester, 'Save'), isTrue);

      await tester.tap(_button('Save'));
      await tester.pump();
      await _settleAll(tester);

      expect(repository.textOf(_mine), 'new text');
      expect(_enabled(tester, 'Save'), isFalse);
      expect(_editorText(tester), 'new text');
      expect(_skills(tester).hasUnsavedEdits, isFalse);

      // Editing back to the saved text is not a change either.
      await tester.enterText(_editor(), 'newer');
      await tester.pump();
      expect(_enabled(tester, 'Save'), isTrue);
      await tester.enterText(_editor(), 'new text');
      await tester.pump();
      expect(_enabled(tester, 'Save'), isFalse);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('switching away from unsaved edits asks', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      await select(tester, 'avera-api-client');
      await tester.enterText(_editor(), 'edited');
      await tester.pump();

      await tester.tap(_row('other-skill'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(_skills(tester).view.selectedId, _mine);
      expect(_editorText(tester), 'edited');

      await tester.tap(_row('other-skill'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      await _settleAll(tester, 2);
      expect(_skills(tester).view.selectedId, 'skill:user:other-skill');
      expect(_editorText(tester), '# other\n');
      expect(repository.textOf(_mine), contains('# API'));
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('switching without edits does not ask', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      await select(tester, 'avera-api-client');

      await select(tester, 'other-skill');

      expect(find.text('Discard changes?'), findsNothing);
      expect(_skills(tester).view.selectedId, 'skill:user:other-skill');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('switching the section with unsaved edits asks too', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      await select(tester, 'avera-api-client');
      await tester.enterText(_editor(), 'edited');
      await tester.pump();

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('page-navigation')),
          matching: find.text('Rules'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(_skills(tester).view.kind, KnowledgeKind.skill);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the global switch turns the skill off for everything', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      await select(tester, 'feature-architecture');

      expect(find.text('Enabled'), findsOneWidget);
      await tester.tap(_globalSwitch());
      await tester.pump();
      await _settleAll(tester, 2);

      expect(repository.calls, contains('setEnabled $_builtin false project=null'));
      expect(
        tester
            .widget<Switch>(find.descendant(of: _globalSwitch(), matching: find.byType(Switch)))
            .value,
        isFalse,
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('exceptions', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      await select(tester, 'feature-architecture');
      expect(find.byTooltip('Remove the exception'), findsNothing);

      await tester.tap(find.text('＋ exception'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('shop_app'));
      await tester.pumpAndSettle();
      await _settleAll(tester, 2);

      expect(repository.calls, contains('setEnabled $_builtin false project=$shopId'));
      expect(find.text('shop_app'), findsOneWidget);
      expect(find.byTooltip('Remove the exception'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove the exception'));
      await tester.pump();
      await _settleAll(tester, 2);

      expect(repository.calls, contains('clearException $_builtin project=$shopId'));
      expect(find.text('shop_app'), findsNothing);
      expect(find.byTooltip('Remove the exception'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a project skill has one switch, for the screen project', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      await select(tester, 'c');

      expect(find.text('All projects'), findsNothing);
      expect(find.text('＋ exception'), findsNothing);
      await tester.tap(_projectSwitch());
      await tester.pump();
      await _settleAll(tester, 2);

      expect(repository.calls, contains('setEnabled skill:project:c false project=$averaId'));
      expect(repository.calls.where((call) => call.contains('project=null')), isEmpty);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('try in chat is only for project skills', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester, withChat: true);
      await select(tester, 'feature-architecture');

      expect(_enabled(tester, 'Try in chat'), isFalse);
      await tester.longPress(_button('Try in chat'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Coming in M3'), findsOneWidget);

      await select(tester, 'c');
      expect(_enabled(tester, 'Try in chat'), isTrue);
      await tester.tap(_button('Try in chat'));
      await tester.pump();
      await tester.pump();

      expect(_data(tester).view, WorkspaceView.chat);
      expect(
        tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget)).textController.text,
        '/c ',
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('try in chat without a chat says so and stays', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      await select(tester, 'c');

      await tester.tap(_button('Try in chat'));
      await tester.pump();

      expect(find.text('Open a chat to try the skill in it'), findsOneWidget);
      expect(_data(tester).view, WorkspaceView.skills);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a skill with a problem shows it', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await select(tester, 'broken');

      expect(find.text('Cannot read the frontmatter'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a rule has the same card without files', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('page-navigation')),
          matching: find.text('Rules'),
        ),
      );
      await tester.pump();

      await select(tester, 'dart-style');

      expect(_editorText(tester), '# dart-style\n');
      expect(find.text('Files'), findsNothing);
      expect(find.text('Duplicate to Mine'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('files are listed for a skill', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await select(tester, 'feature-architecture');

      expect(find.text('Files'), findsOneWidget);
      expect(find.text('SKILL.md'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('When to use'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('Adding', () {
    testWidgets('create validates the name', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await chooseAdd(tester, 'Create');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Lowercase letters, digits and hyphens, up to 64 characters'),
        findsOneWidget,
      );
      await submitName(tester, 'Bad Name');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('This name is not allowed'), findsOneWidget);

      await submitName(tester, 'avera-api-client');
      expect(find.text('There is already an item with this name'), findsOneWidget);
      expect(find.textContaining('This name is not allowed'), findsNothing);

      await submitName(tester, 'ok-name');
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(_skills(tester).view.selectedId, 'skill:user:ok-name');
      expect(find.text('Something went wrong'), findsNothing);
      expect(_editorText(tester), contains('# ok-name'));
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('create in the rules section makes a rule and has no folder import', (
      tester,
    ) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('page-navigation')),
          matching: find.text('Rules'),
        ),
      );
      await tester.pump();

      await openAddMenu(tester);
      expect(find.text('From folder…'), findsNothing);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await submitName(tester, 'my-rule');
      await tester.pumpAndSettle();

      expect(_skills(tester).view.selectedId, 'rule:user:my-rule');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('cancelling the name dialog creates nothing', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await chooseAdd(tester, 'Create');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.calls.where((call) => call.startsWith('create')), isEmpty);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('from git says M3', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await chooseAdd(tester, 'From git repository…');

      expect(find.text('Coming in M3'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('from folder imports the picked folder and opens it', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      final pickedWith = <String>[];
      _skills(tester).pickFolder = (confirmText) async {
        pickedWith.add(confirmText);
        return '/imports/pretty';
      };

      await chooseAdd(tester, 'From folder…');
      await _settleAll(tester);

      expect(pickedWith, ['Choose a skill folder']);
      expect(repository.calls, contains('importFolder /imports/pretty'));
      expect(_skills(tester).view.selectedId, 'skill:user:pretty');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a cancelled folder picker does nothing', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      _skills(tester).pickFolder = (_) async => null;

      await chooseAdd(tester, 'From folder…');
      await _settleAll(tester);

      expect(repository.calls.where((call) => call.startsWith('importFolder')), isEmpty);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a folder without SKILL.md says so', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);
      _skills(tester).pickFolder = (_) async => '/imports/empty';

      await chooseAdd(tester, 'From folder…');
      await _settleAll(tester);

      expect(
        find.text('This folder cannot be used as a skill. It needs a SKILL.md file.'),
        findsOneWidget,
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('generate with an agent opens a chat with the prompt', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      await chooseAdd(tester, 'Generate with an agent');
      for (var i = 0; i < 5; i++) {
        await _settle(tester);
      }

      expect(_data(tester).view, WorkspaceView.chat);
      expect(_data(tester).projectId, averaId);
      expect(
        tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget)).textController.text,
        _generatePrompt,
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('generate with an agent needs a project', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester, selectProject: false);

      await openAddMenu(tester);
      await tester.tap(find.text('Generate with an agent'));
      await tester.pumpAndSettle();

      expect(_data(tester).view, WorkspaceView.skills);
      expect(_data(tester).sessionId, isNull);
      // The menu stays open: the row is disabled.
      expect(find.text('Create'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('Failed actions say so', () {
    testWidgets('a failed switch shows a message', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      // A project item has no global switch, so the repository refuses it.
      _skills(tester).actions.setEnabled('skill:project:c', enabled: false);
      await tester.pump();
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('writing to a built-in item says it is read-only', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      _skills(tester).actions.save(_builtin, 'x');
      await tester.pump();
      await tester.pump();

      expect(find.text('Built-in items cannot be changed'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('an item that is gone says it was not found', (tester) async {
      useDesktopView(tester);
      await pumpScreen(tester);

      _skills(tester).actions.save('skill:user:gone', 'x');
      await tester.pump();
      await tester.pump();

      expect(find.text('It was not found. It may have been deleted.'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });
  });

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
        ).copyWith(
          title: 'A skill with a really long name that goes on and on and on and on',
          whenToUse: 'When the user asks for something long. ' * 6,
          version: '12.34.56',
          problem: 'The frontmatter is broken in a really long and detailed way. ' * 3,
          files: [for (var i = 0; i < 12; i++) 'templates/some-long-file-name-$i.dart'],
        ),
        memorySkill('short', source: SkillSource.user),
      ],
      projectItems: {
        _averaRoot: [memorySkill('release-checklist', source: SkillSource.project)],
        _shopRoot: const [],
      },
      texts: {
        'skill:builtin:a-skill-with-a-really-long-name-that-goes-on-and-on-and-on': List.generate(
          60,
          (i) => 'line $i ' * 20,
        ).join('\n'),
        'skill:user:short': 'x',
        'skill:project:release-checklist': 'y',
      },
    );
    await pumpScreen(tester, locale: locale, theme: dark ? AppTheme.dark() : AppTheme.light());

    for (final name in const [
      'A skill with a really long name that goes on and on and on and on',
      'short',
      'release-checklist',
    ]) {
      await select(tester, name);
      expect(tester.takeException(), isNull, reason: name);
    }
    // Exceptions make the scope row longer.
    await select(tester, 'short');
    _skills(tester).actions.setEnabled('skill:user:short', enabled: false, projectId: shopId);
    await _settleAll(tester, 2);
    _skills(tester).actions.setEnabled('skill:user:short', enabled: false, projectId: averaId);
    await _settleAll(tester, 2);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(locale.languageCode == 'ru' ? '＋ Добавить' : '＋ Add'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(5, 590));
    await tester.pumpAndSettle();
    await disposeTestApp(tester, dependencies);
  }

  group('Layout', () {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      for (final dark in const [false, true]) {
        testWidgets(
          'the card does not overflow at 900×600 in ${locale.languageCode}, ${dark ? 'dark' : 'light'}',
          (tester) => noOverflow(tester, const Size(900, 600), locale, dark: dark),
        );
      }
    }
  });
}
