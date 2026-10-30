import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/command_suggestions.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_config_widget.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/skills_list.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_skills_repository.dart';
import '../../support/test_app.dart';

const String _root = '/work/avera-hotel';

const String _chipTooltip = 'Skills enabled for this project';

/// [text] inside the `/` menu (the chip of the toolbar says the same word).
Finder _inMenu(String text) =>
    find.descendant(of: find.byType(CommandSuggestions), matching: find.text(text));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late MemorySkillsRepository repository;
  late int projectId;
  late int sessionId;

  setUp(() {
    repository = MemorySkillsRepository(
      items: [memorySkill('feature-architecture', description: 'Build a feature')],
      projectItems: {
        _root: [
          memorySkill('drift-migration', source: SkillSource.project, description: 'New schema'),
          memorySkill('checklist', source: SkillSource.project, description: 'Before a release'),
        ],
      },
    );
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// A window with one project and its chat opened.
  Future<void> pumpChat(WidgetTester tester) async {
    useDesktopView(tester);
    dependencies = testDependencies(skillsRepository: repository);
    await tester.runAsync(() async {
      final database = dependencies.database;
      projectId = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: _root, name: 'avera-hotel'));
      sessionId = await database
          .into(database.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: projectId,
              agentId: 'claude',
              title: const Value<String>('The chat'),
            ),
          );
    });
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('The chat'));
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
  }

  WorkspaceConfigWidgetState workspaceOf(WidgetTester tester) =>
      WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

  Finder chip() => find.byTooltip(_chipTooltip);

  Finder chipCount(String count) => find.descendant(of: chip(), matching: find.text(count));

  group('the chip', () {
    testWidgets('counts enabled skills of the chat project', (tester) async {
      await pumpChat(tester);

      expect(chipCount('3'), findsOneWidget);
      expect(
        find.descendant(of: chip(), matching: find.byIcon(Icons.extension_outlined)),
        findsOneWidget,
      );

      await tester.runAsync(
        () =>
            repository.setEnabled('skill:project:checklist', enabled: false, projectId: projectId),
      );
      await settle(tester);

      expect(chipCount('2'), findsOneWidget);
      expect(chipCount('3'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('follows the project of the window', (tester) async {
      await pumpChat(tester);

      expect(repository.calls, contains('watch project=$projectId root=$_root'));
      await disposeTestApp(tester, dependencies);
    });
  });

  group('menu F', () {
    testWidgets('lists enabled skills first and opens the library', (tester) async {
      await pumpChat(tester);
      await tester.runAsync(
        () => repository.setEnabled(
          'skill:builtin:feature-architecture',
          enabled: false,
          projectId: projectId,
        ),
      );
      await settle(tester);

      final badges = find.byType(PreviewBadge).evaluate().length;
      await tester.tap(chip());
      await tester.pumpAndSettle();

      expect(find.text('Enabled for avera-hotel'), findsOneWidget);
      final names = ['checklist', 'drift-migration', 'feature-architecture'];
      final ys = [for (final name in names) tester.getTopLeft(find.text(name)).dy];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'enabled first, disabled last');
      expect(find.text('Before a release'), findsOneWidget);
      // The note says the rows do not switch yet, and carries the Preview badge.
      expect(find.textContaining('come in M3'), findsOneWidget);
      expect(find.byType(PreviewBadge), findsNWidgets(badges + 1));

      await tester.tap(find.text('Open the skill library →'));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(workspaceOf(tester).dataController.view, WorkspaceView.skills);
      expect(
        SkillsConfigInhWidget.of(tester.element(find.byType(SkillsList))).view.projectId,
        projectId,
      );
      await disposeTestApp(tester, dependencies);
    });
  });

  group('in Russian', () {
    testWidgets('the chip, its menu and the / menu fit', (tester) async {
      useDesktopView(tester);
      dependencies = testDependencies(skillsRepository: repository);
      await tester.runAsync(() async {
        final database = dependencies.database;
        projectId = await database
            .into(database.projectsTable)
            .insert(ProjectsTableCompanion.insert(path: _root, name: 'avera-hotel'));
        await database
            .into(database.sessionsTable)
            .insert(
              SessionsTableCompanion.insert(
                projectId: projectId,
                agentId: 'claude',
                title: const Value<String>('Чат'),
              ),
            );
      });
      await tester.pumpWidget(
        testApp(
          const WorkspaceConfigWidget(),
          dependencies: dependencies,
          withSettings: true,
          locale: const Locale('ru'),
        ),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Чат'));
      for (var i = 0; i < 5; i++) {
        await settle(tester);
      }

      await tester.tap(find.byTooltip('Скиллы, включённые для проекта'));
      await tester.pumpAndSettle();
      expect(find.text('Включены для avera-hotel'), findsOneWidget);
      expect(find.text('Открыть библиотеку скиллов →'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      expect(_inMenu('Скиллы'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('the / menu', () {
    testWidgets('shows project skills first; only project skills can be inserted', (tester) async {
      await pumpChat(tester);

      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();

      expect(_inMenu('Skills'), findsOneWidget);
      final skillsY = tester.getTopLeft(_inMenu('Skills')).dy;
      expect(skillsY, lessThan(tester.getTopLeft(find.text('App')).dy));
      // The built-in skill is dimmed and says when it comes.
      expect(find.text('/feature-architecture'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('/feature-architecture'), matching: find.byType(Opacity)),
          matching: find.text('Coming in M3'),
        ),
        findsWidgets,
      );
      await tester.tap(find.text('/feature-architecture'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '/');

      // Enter takes the first row that can be inserted: a project skill.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '/checklist ');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('does not list skills turned off for the project', (tester) async {
      await pumpChat(tester);
      await tester.runAsync(
        () =>
            repository.setEnabled('skill:project:checklist', enabled: false, projectId: projectId),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();

      expect(find.text('/checklist'), findsNothing);
      expect(find.text('/drift-migration'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('the feed', () {
    testWidgets('a skill line opens the skill', (tester) async {
      await pumpChat(tester);
      final live = await tester.runAsync(() => dependencies.agentHub.session(sessionId));
      await tester.runAsync(() async {
        live!.store.addAgentFrame('tool_call', <String, Object?>{
          'params': <String, Object?>{
            'update': <String, Object?>{
              'toolCallId': 't1',
              'title': 'Load skill: drift-migration',
              'kind': 'other',
              'status': 'completed',
            },
          },
        });
        await live.store.flush();
      });
      await settle(tester);

      expect(find.text('Skill'), findsOneWidget);
      await tester.tap(find.text('drift-migration'));
      await tester.pumpAndSettle();
      await settle(tester);

      expect(workspaceOf(tester).dataController.view, WorkspaceView.skills);
      final view = SkillsConfigInhWidget.of(tester.element(find.byType(SkillsList))).view;
      expect(view.selectedId, 'skill:project:drift-migration');
      await disposeTestApp(tester, dependencies);
    });
  });

  group('ChatSkills', () {
    ChatSkills of(List<KnowledgeItem> skills) =>
        ChatSkills.of(SkillLibrary(skills: skills), projectName: 'p');

    test('equal content is equal, so the composer does not rebuild', () {
      final first = of([memorySkill('a', source: SkillSource.project, description: 'x')]);
      final again = of([memorySkill('a', source: SkillSource.project, description: 'x')]);

      expect(again, first);
      expect(again.hashCode, first.hashCode);
    });

    test('differs when a skill is switched off or changes', () {
      final on = of([memorySkill('a', source: SkillSource.project)]);
      final off = of([memorySkill('a', source: SkillSource.project).copyWith(enabled: false)]);
      final described = of([memorySkill('a', source: SkillSource.project, description: 'x')]);

      expect(off, isNot(on));
      expect(described, isNot(on));
      expect(ChatSkills.empty, isNot(on));
    });

    test('counts the enabled skills and puts project skills first, then mine, then built-in', () {
      final skills = of([
        memorySkill('b-built-in'),
        memorySkill('a-mine', source: SkillSource.user).copyWith(enabled: false),
        memorySkill('c-project', source: SkillSource.project),
      ]);

      expect(skills.enabledCount, 2);
      expect(
        [for (final skill in skills.skills) skill.name],
        ['c-project', 'a-mine', 'b-built-in'],
      );
      expect(skills.skills.first.invocable, isTrue);
      expect(skills.skills.last.invocable, isFalse);
    });

    test('an unchanged emission leaves the composer notifier silent', () {
      final notifier = ValueNotifier<ChatSkills>(of([memorySkill('a')]));
      var notified = 0;
      notifier
        ..addListener(() => notified++)
        ..value = of([memorySkill('a')]);

      expect(notified, 0);
      notifier.value = of([memorySkill('a'), memorySkill('b')]);
      expect(notified, 1);
    });
  });
}
