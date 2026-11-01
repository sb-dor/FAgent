import 'dart:async';
import 'dart:io';

import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_tool.dart';
import 'package:flutter_code_agent/src/feature/app_mcp_tools/data/skill_tools.dart';
import 'package:flutter_code_agent/src/feature/skills/data/builtin_knowledge.dart';
import 'package:flutter_code_agent/src/feature/skills/data/chat_skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/memory_skills_repository.dart';

const AppMcpCaller _caller = (sessionId: 7, projectId: 1);

final class _ChatSkills implements IChatSkillsRepository {
  final Map<String, bool> states = <String, bool>{};

  @override
  Future<Map<String, bool>> current(int sessionId) async => Map.of(states);

  @override
  Stream<Map<String, bool>> watch(int sessionId) => throw UnimplementedError();

  @override
  Future<void> set(
    int sessionId,
    String skillId, {
    required bool enabled,
    required bool projectEnabled,
  }) => throw UnimplementedError();
}

final class _Builtin implements IBuiltinKnowledge {
  const _Builtin(this.files);

  final Map<String, String> files;

  @override
  Future<Map<String, String>> load() async => files;
}

String _text(AppMcpResult result) => switch (result) {
  AppMcpText(:final text) => text,
  AppMcpError(:final message) => 'ERROR: $message',
  AppMcpImage() => 'IMAGE',
};

void main() {
  late Directory temp;
  late Directory userSkill;
  late MemorySkillsRepository skills;
  late _ChatSkills chat;
  late ListSkillsTool list;
  late LoadSkillTool load;
  late ReadSkillFileTool read;

  KnowledgeItem userItem(String name, String path) => KnowledgeItem(
    id: 'skill:user:$name',
    kind: KnowledgeKind.skill,
    source: SkillSource.user,
    name: name,
    title: name,
    description: 'The $name skill',
    path: path,
    files: const ['SKILL.md', 'notes.txt'],
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('skill_tools_test');
    userSkill = Directory(p.join(temp.path, 'mine'))..createSync();
    File(p.join(userSkill.path, 'SKILL.md')).writeAsStringSync('---\nname: mine\n---\nMine text');
    File(p.join(userSkill.path, 'notes.txt')).writeAsStringSync('Некоторые заметки');
    Directory(p.join(userSkill.path, 'sub')).createSync();
    File(p.join(userSkill.path, 'sub', 'deep.txt')).writeAsStringSync('deep');
    File(p.join(temp.path, 'secret.txt')).writeAsStringSync('top secret');
    Link(p.join(userSkill.path, 'escape.txt')).createSync(p.join(temp.path, 'secret.txt'));
    Link(p.join(userSkill.path, 'escape-dir')).createSync(temp.path);
    File(p.join(userSkill.path, 'binary.dat')).writeAsBytesSync([0xff, 0xfe, 0x00, 0xc3, 0x28]);
    File(p.join(userSkill.path, 'big.txt')).writeAsStringSync('a' * (skillFileLimit + 1));
    File(p.join(userSkill.path, 'limit.txt')).writeAsStringSync('a' * skillFileLimit);

    skills = MemorySkillsRepository(
      items: [
        memorySkill(
          'arch',
          description: 'Architecture',
        ).copyWith(path: 'skills/arch', files: const ['SKILL.md', 'templates/a.dart']),
        userItem('mine', userSkill.path),
        memorySkill('claudes-own', source: SkillSource.project),
      ],
      texts: {
        'skill:builtin:arch': '---\nname: arch\n---\nArch text',
        'skill:user:mine': '---\nname: mine\n---\nMine text',
      },
    );
    chat = _ChatSkills();
    final catalog = ChatSkillCatalog(skills: skills, chatSkills: chat);
    list = ListSkillsTool(catalog: catalog);
    load = LoadSkillTool(catalog: catalog, skills: skills);
    read = ReadSkillFileTool(
      catalog: catalog,
      builtin: _Builtin({
        'skills/arch/SKILL.md': 'Arch text',
        'skills/arch/templates/a.dart': 'class A {}',
        'skills/arch-extra/SKILL.md': 'other skill',
        'rules/architecture.md': 'a rule',
        'skills/arch/big.txt': 'x' * (256 * 1024 + 1),
      }),
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<String> readFile(String name, Object? path) async =>
      _text(await read.call(_caller, {'name': name, 'path': path}));

  test('every tool has an object input schema', () {
    for (final tool in <AppMcpTool>[list, load, read]) {
      expect(tool.inputSchema['type'], 'object', reason: tool.name);
      expect(tool.inputSchema['properties'], isA<Map<String, Object?>>(), reason: tool.name);
    }
  });

  group('list_skills', () {
    test('lists built-in and user skills, not the project ones', () async {
      final text = _text(await list.call(_caller, {}));

      expect(text, contains('- arch (builtin): Architecture'));
      expect(text, contains('- mine (user): The mine skill'));
      expect(text, isNot(contains('claudes-own')));
    });

    test('leaves out a skill switched off in the chat', () async {
      chat.states['skill:user:mine'] = false;

      final text = _text(await list.call(_caller, {}));

      expect(text, contains('arch'));
      expect(text, isNot(contains('mine')));
    });

    test('leaves out a skill switched off in the project', () async {
      await skills.setEnabled('skill:builtin:arch', enabled: false, projectId: 1);

      expect(_text(await list.call(_caller, {})), isNot(contains('arch')));
      // Another project still has it.
      expect(_text(await list.call((sessionId: 8, projectId: 2), {})), contains('arch'));
    });

    test('says so when nothing is on', () async {
      chat.states
        ..['skill:user:mine'] = false
        ..['skill:builtin:arch'] = false;

      expect(_text(await list.call(_caller, {})), 'No skills are on for this chat');
    });
  });

  group('load_skill', () {
    test('returns SKILL.md and the file list', () async {
      final text = _text(await load.call(_caller, {'name': 'mine'}));

      expect(text, startsWith('---\nname: mine\n---\nMine text'));
      expect(text, endsWith('\n\nFiles:\n- SKILL.md\n- notes.txt'));
    });

    test('refuses a skill that is off for the chat', () async {
      chat.states['skill:user:mine'] = false;

      expect(
        _text(await load.call(_caller, {'name': 'mine'})),
        'ERROR: Skill mine is off for this chat',
      );
    });

    test('says an unknown skill is not found', () async {
      expect(_text(await load.call(_caller, {'name': 'x'})), 'ERROR: Skill not found: x');
    });

    test('does not serve a project skill', () async {
      expect(
        _text(await load.call(_caller, {'name': 'claudes-own'})),
        'ERROR: Skill not found: claudes-own',
      );
    });

    test('needs a name', () async {
      expect(_text(await load.call(_caller, {})), startsWith('ERROR:'));
      expect(_text(await load.call(_caller, {'name': 3})), startsWith('ERROR:'));
    });
  });

  group('read_skill_file', () {
    test('reads a text file of a user skill, also in a subfolder', () async {
      expect(await readFile('mine', 'notes.txt'), 'Некоторые заметки');
      expect(await readFile('mine', 'sub/deep.txt'), 'deep');
      expect(await readFile('mine', './sub/../notes.txt'), 'Некоторые заметки');
    });

    test('reads a built-in file from the assets', () async {
      expect(await readFile('arch', 'templates/a.dart'), 'class A {}');
      expect(await readFile('arch', 'SKILL.md'), 'Arch text');
    });

    test('refuses a path outside the skill', () async {
      for (final path in <String>[
        '../secret.txt',
        'sub/../../secret.txt',
        '..',
        '/etc/passwd',
        p.join(temp.path, 'secret.txt'),
        'escape.txt',
        'escape-dir/secret.txt',
        'a\u0000b',
      ]) {
        expect(await readFile('mine', path), 'ERROR: Path is outside the skill', reason: path);
      }
    });

    test('keeps a built-in skill to its own folder', () async {
      for (final path in <String>[
        '../arch-extra/SKILL.md',
        '../../rules/architecture.md',
        '/skills/arch/SKILL.md',
      ]) {
        expect(await readFile('arch', path), 'ERROR: Path is outside the skill', reason: path);
      }
      expect(await readFile('arch', 'nothing.md'), 'ERROR: File not found: nothing.md');
    });

    test('says a missing file or a folder is not readable', () async {
      expect(await readFile('mine', 'missing.txt'), 'ERROR: File not found: missing.txt');
      expect(await readFile('mine', 'sub'), 'ERROR: Not a file: sub');
    });

    test('refuses a file that is not UTF-8 text', () async {
      expect(await readFile('mine', 'binary.dat'), 'ERROR: Not a text file');
    });

    test('refuses a file over the limit and reads one at the limit', () async {
      expect(await readFile('mine', 'big.txt'), 'ERROR: File is too large');
      expect(await readFile('mine', 'limit.txt'), hasLength(skillFileLimit));
      expect(await readFile('arch', 'big.txt'), 'ERROR: File is too large');
    });

    test('follows the chat switch', () async {
      chat.states['skill:user:mine'] = false;

      expect(await readFile('mine', 'notes.txt'), 'ERROR: Skill mine is off for this chat');
      expect(await readFile('nope', 'notes.txt'), 'ERROR: Skill not found: nope');
    });

    test('needs a path', () async {
      expect(await readFile('mine', null), startsWith('ERROR:'));
      expect(await readFile('mine', ''), startsWith('ERROR:'));
    });
  });

  group('a user copy of a built-in skill (Duplicate keeps the name)', () {
    setUp(() {
      final copy = Directory(p.join(temp.path, 'arch'))..createSync();
      File(p.join(copy.path, 'SKILL.md')).writeAsStringSync('My arch text');
      File(p.join(copy.path, 'notes.txt')).writeAsStringSync('my notes');
      skills = MemorySkillsRepository(
        items: [
          memorySkill(
            'arch',
            description: 'Architecture',
          ).copyWith(path: 'skills/arch', files: const ['SKILL.md', 'templates/a.dart']),
          userItem('arch', copy.path),
        ],
        texts: {'skill:builtin:arch': 'Arch text', 'skill:user:arch': 'My arch text'},
      );
      final catalog = ChatSkillCatalog(skills: skills, chatSkills: chat);
      list = ListSkillsTool(catalog: catalog);
      load = LoadSkillTool(catalog: catalog, skills: skills);
      read = ReadSkillFileTool(
        catalog: catalog,
        builtin: const _Builtin({'skills/arch/SKILL.md': 'Arch text'}),
      );
    });

    test('load_skill and read_skill_file serve the user copy', () async {
      expect(_text(await load.call(_caller, {'name': 'arch'})), startsWith('My arch text'));
      expect(await readFile('arch', 'notes.txt'), 'my notes');
    });

    test('with the built-in one off, the user copy still loads', () async {
      await skills.setEnabled('skill:builtin:arch', enabled: false, projectId: 1);

      expect(_text(await load.call(_caller, {'name': 'arch'})), startsWith('My arch text'));
      expect(_text(await list.call(_caller, {})), '- arch (user): The arch skill');
    });

    test('with the user copy off in the chat, the built-in one loads', () async {
      chat.states['skill:user:arch'] = false;

      expect(_text(await load.call(_caller, {'name': 'arch'})), startsWith('Arch text'));
      expect(_text(await list.call(_caller, {})), '- arch (builtin): Architecture');
    });

    test('with both off, the skill is off for this chat', () async {
      chat.states
        ..['skill:user:arch'] = false
        ..['skill:builtin:arch'] = false;

      expect(
        _text(await load.call(_caller, {'name': 'arch'})),
        'ERROR: Skill arch is off for this chat',
      );
    });

    test('list_skills lists the name once, as the user copy', () async {
      expect(_text(await list.call(_caller, {})), '- arch (user): The arch skill');
    });
  });
}
