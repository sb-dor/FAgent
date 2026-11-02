import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_skills_repository.dart';
import '../../support/test_app.dart';

/// The choices of one chat, fixed.
final class _FixedChatSkills implements IChatSkillsRepository {
  _FixedChatSkills(this.states);

  final Map<String, bool> states;

  @override
  Stream<Map<String, bool>> watch(int sessionId) => Stream<Map<String, bool>>.value(states);

  @override
  Future<Map<String, bool>> current(int sessionId) async => states;

  @override
  Future<void> set(
    int sessionId,
    String skillId, {
    required bool enabled,
    required bool projectEnabled,
  }) async {}
}

Map<String, Object?> _resource(String name, String text) => <String, Object?>{
  'type': 'resource',
  'resource': <String, Object?>{
    'uri': 'skill://$name/SKILL.md',
    'mimeType': 'text/markdown',
    'text': text,
  },
};

void main() {
  late Dependencies dependencies;
  late MemorySkillsRepository skills;

  ChatSkills library() => ChatSkills.of(
    SkillLibrary(
      skills: [
        memorySkill('feature-architecture'),
        memorySkill('mine', source: SkillSource.user),
        memorySkill('release', source: SkillSource.project),
        memorySkill('project-off').copyWith(enabled: false),
      ],
    ),
    projectName: 'p',
  );

  setUp(() {
    skills = MemorySkillsRepository(
      items: [
        memorySkill('feature-architecture'),
        memorySkill('mine', source: SkillSource.user),
      ],
      texts: {
        'skill:builtin:feature-architecture': '# Feature architecture\n',
        'skill:user:mine': '# Mine\n',
      },
    );
  });

  Future<ChatConfigWidgetState> pumpChat(
    WidgetTester tester, {
    Map<String, bool> chatStates = const <String, bool>{},
  }) async {
    dependencies = testDependencies(
      skillsRepository: skills,
      chatSkillsRepository: _FixedChatSkills(chatStates),
    );
    addTearDown(dependencies.database.close);
    await tester.pumpWidget(
      testApp(
        dependencies: dependencies,
        ChatConfigWidget(
          sessionId: 404,
          project: const Project(id: 1, path: '/nowhere', name: 'p', isFlutter: false),
          chatSkills: library(),
          onOpenSkills: ({itemId, projectId}) {},
        ),
      ),
    );
    await tester.pump();
    return tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));
  }

  Future<({String text, List<Map<String, Object?>> resources})> compose(
    WidgetTester tester,
    ChatConfigWidgetState chat,
    String text,
  ) async {
    late ({String text, List<Map<String, Object?>> resources}) found;
    await tester.runAsync(() async => found = await chat.promptFor(text));
    return found;
  }

  testWidgets('/skill of a built-in skill sends the rest and embeds SKILL.md', (tester) async {
    final chat = await pumpChat(tester);

    final prompt = await compose(tester, chat, '/feature-architecture add a todo feature');

    expect(prompt.text, 'add a todo feature');
    expect(prompt.resources, [_resource('feature-architecture', '# Feature architecture\n')]);
  });

  testWidgets('a command alone asks to use the skill', (tester) async {
    final chat = await pumpChat(tester);

    final prompt = await compose(tester, chat, '/feature-architecture');

    expect(prompt.text, 'Use the feature-architecture skill.');
    expect(prompt.resources, [_resource('feature-architecture', '# Feature architecture\n')]);
  });

  testWidgets('a skill of mine is embedded the same way', (tester) async {
    final chat = await pumpChat(tester);

    final prompt = await compose(tester, chat, '/mine do it');

    expect(prompt.text, 'do it');
    expect(prompt.resources, [_resource('mine', '# Mine\n')]);
  });

  testWidgets('a project skill stays plain text: Claude reads .claude/skills itself', (
    tester,
  ) async {
    final chat = await pumpChat(tester);

    final prompt = await compose(tester, chat, '/release now');

    expect(prompt.text, '/release now');
    expect(prompt.resources, isEmpty);
  });

  testWidgets('a skill the chat turned off stays plain text, without a resource', (tester) async {
    final chat = await pumpChat(tester, chatStates: {'skill:builtin:feature-architecture': false});

    final prompt = await compose(tester, chat, '/feature-architecture add a todo');

    expect(prompt.text, '/feature-architecture add a todo');
    expect(prompt.resources, isEmpty);
  });

  testWidgets('a skill the project turned off stays plain text', (tester) async {
    final chat = await pumpChat(tester);

    final prompt = await compose(tester, chat, '/project-off');

    expect(prompt.text, '/project-off');
    expect(prompt.resources, isEmpty);
  });

  testWidgets('an unknown command or a command in the middle is plain text', (tester) async {
    final chat = await pumpChat(tester);

    expect((await compose(tester, chat, '/nothing here')).text, '/nothing here');
    final middle = await compose(tester, chat, 'please /feature-architecture');
    expect(middle.text, 'please /feature-architecture');
    expect(middle.resources, isEmpty);
  });

  testWidgets('a SKILL.md that cannot be read leaves the text as typed', (tester) async {
    skills = MemorySkillsRepository(items: [memorySkill('feature-architecture')]);
    final chat = await pumpChat(tester);

    final prompt = await compose(tester, chat, '/feature-architecture add a todo');

    expect(prompt.text, '/feature-architecture add a todo');
    expect(prompt.resources, isEmpty);
  });

  testWidgets('the skill resource comes before the mentioned files', (tester) async {
    final chat = await pumpChat(tester);

    final prompt = await compose(tester, chat, '/mine see @nothing.md');

    expect(prompt.resources.first, _resource('mine', '# Mine\n'));
  });
}
