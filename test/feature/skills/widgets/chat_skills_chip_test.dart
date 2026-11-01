import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:flutter_code_agent/src/feature/skills/widgets/chat_skills_chip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/memory_skills_repository.dart';
import '../../../support/test_app.dart';

ChatSkills _skills() => ChatSkills.of(
  SkillLibrary(
    skills: [
      memorySkill('feature-architecture', description: 'Build a feature'),
      memorySkill('checklist', source: SkillSource.project, description: 'Before a release'),
      memorySkill('off-for-project').copyWith(enabled: false),
    ],
  ),
  projectName: 'avera-hotel',
);

typedef _Toggle = ({String name, bool enabled});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Future<List<_Toggle>> pump(
    WidgetTester tester, {
    Map<String, bool> chatStates = const <String, bool>{},
    Locale locale = const Locale('en'),
  }) async {
    useDesktopView(tester);
    final toggles = <_Toggle>[];
    await tester.pumpWidget(
      testApp(
        ChatSkillsChip(
          skills: _skills(),
          chatStates: chatStates,
          onToggle: (skill, {required enabled}) =>
              toggles.add((name: skill.name, enabled: enabled)),
          onOpenLibrary: () {},
        ),
        locale: locale,
      ),
    );
    return toggles;
  }

  Finder boxOf(String name, IconData icon) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(GestureDetector)).first,
    matching: find.byIcon(icon),
  );

  testWidgets('lists the skills of the project with checkboxes and counts the ones that are on', (
    tester,
  ) async {
    await pump(tester, chatStates: {'skill:builtin:feature-architecture': false});

    expect(
      find.descendant(of: find.byType(ChatSkillsChip), matching: find.text('1')),
      findsOneWidget,
    );
    await tester.tap(find.byType(ChatSkillsChip));
    await tester.pumpAndSettle();

    expect(find.text('Enabled for avera-hotel'), findsOneWidget);
    expect(boxOf('checklist', Icons.check_box), findsOneWidget);
    expect(boxOf('feature-architecture', Icons.check_box_outline_blank), findsOneWidget);
    expect(find.text('off-for-project'), findsNothing, reason: 'the project has it off');
    expect(find.text('Build a feature'), findsOneWidget);
  });

  testWidgets('a project skill says when a change applies', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(ChatSkillsChip));
    await tester.pumpAndSettle();

    expect(find.text('Applies when the chat is reopened'), findsOneWidget);
    expect(find.text('Before a release'), findsNothing);
  });

  testWidgets('choosing a row flips the skill for the chat', (tester) async {
    final toggles = await pump(tester, chatStates: {'skill:builtin:feature-architecture': false});
    await tester.tap(find.byType(ChatSkillsChip));
    await tester.pumpAndSettle();

    await tester.tap(find.text('checklist'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ChatSkillsChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature-architecture'));
    await tester.pumpAndSettle();

    expect(toggles, [
      (name: 'checklist', enabled: false),
      (name: 'feature-architecture', enabled: true),
    ]);
  });

  testWidgets('in Russian', (tester) async {
    await pump(tester, locale: const Locale('ru'));
    await tester.tap(find.byType(ChatSkillsChip));
    await tester.pumpAndSettle();

    expect(find.text('Применится при повторном открытии чата'), findsOneWidget);
    expect(find.text('Включены для avera-hotel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
