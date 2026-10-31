import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/skill_call.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_item_view.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

ToolCallItem _call(String title, {String? kind = 'other', String status = 'completed'}) =>
    ToolCallItem(0, toolCallId: 't', title: title, kind: kind, status: status);

ChatSkill _skill(String name, SkillSource source) => ChatSkill(
  id: 'skill:${source.name}:$name',
  name: name,
  description: '',
  source: source,
  enabled: true,
  invocable: source == SkillSource.project,
);

Widget _view(
  ToolCallItem call, {
  ChatSkills skills = ChatSkills.empty,
  ValueChanged<String>? open,
}) => testApp(
  Align(
    alignment: Alignment.topCenter,
    child: ChatItemView(
      item: call,
      onAnswerPermission: (_, _) {},
      skills: skills,
      onOpenSkill: open,
    ),
  ),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('skillNameOf', () {
    test('takes the name from the title the adapter gives a Skill call', () {
      expect(skillNameOf(_call('Load skill: drift-migration')), 'drift-migration');
    });

    test('is null for a title without a name', () {
      expect(skillNameOf(_call('Load skill')), isNull);
      expect(skillNameOf(_call('Load skill:   ')), isNull);
    });

    test('is null for any other tool', () {
      expect(skillNameOf(_call('Read file', kind: 'read')), isNull);
      expect(skillNameOf(_call('Load skills: a')), isNull);
    });
  });

  group('the skill line', () {
    testWidgets('shows the skill name with the skill icon instead of a tool row', (tester) async {
      await tester.pumpWidget(_view(_call('Load skill: drift-migration')));

      expect(find.text('drift-migration'), findsOneWidget);
      expect(find.byIcon(Icons.extension_outlined), findsOneWidget);
      expect(find.byIcon(Icons.build_outlined), findsNothing);
      expect(find.text('Load skill: drift-migration'), findsNothing);
    });

    testWidgets('opens the first skill of that name: project, then mine, then built-in', (
      tester,
    ) async {
      final opened = <String>[];
      await tester.pumpWidget(
        _view(
          _call('Load skill: shared'),
          skills: ChatSkills(
            projectName: 'p',
            skills: <ChatSkill>[
              _skill('shared', SkillSource.builtin),
              _skill('shared', SkillSource.user),
              _skill('shared', SkillSource.project),
            ],
          ),
          open: opened.add,
        ),
      );

      await tester.tap(find.text('shared'));

      expect(opened, <String>['skill:project:shared']);
    });

    testWidgets('is not clickable when the library has no such skill', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        _view(
          _call('Load skill: unknown'),
          skills: ChatSkills(
            projectName: 'p',
            skills: <ChatSkill>[_skill('other', SkillSource.project)],
          ),
          open: opened.add,
        ),
      );

      await tester.tap(find.text('unknown'));

      expect(opened, isEmpty);
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
