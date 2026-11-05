import 'dart:io';

import 'package:flutter_code_agent/src/feature/project_rules/data/project_rules_repository.dart';
import 'package:flutter_code_agent/src/feature/project_rules/models/project_rule.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/memory_skills_repository.dart';

void main() {
  late Directory project;
  late _RecordingProjects projects;
  late ProjectRulesRepositoryImpl repository;

  setUp(() async {
    project = Directory.systemTemp.createTempSync('project_rules');
    addTearDown(() => project.deleteSync(recursive: true));
    projects = _RecordingProjects();
    final skills = MemorySkillsRepository(
      items: [
        memoryRule('architecture', description: 'Layout and layers.'),
        memoryRule('widgets', description: 'Widget conventions.'),
        memoryRule('style', source: SkillSource.user, description: 'Mine.'),
      ],
      texts: {
        'rule:builtin:architecture': '---\nname: architecture\ndescription: "A"\n---\n\n# Arch\n',
        'rule:builtin:widgets': '---\nname: widgets\ndescription: "W"\n---\n\n# Widgets\n',
        'rule:user:style': '# Style\n',
      },
    );
    await skills.setEnabled('rule:builtin:widgets', enabled: false);
    repository = ProjectRulesRepositoryImpl(skills: skills, projects: projects);
  });

  String read(String relative) => File(p.join(project.path, relative)).readAsStringSync();

  test('builtinRules lists the built-in rules only, with their switch', () async {
    expect(await repository.builtinRules(), const <ProjectRule>[
      ProjectRule(
        id: 'rule:builtin:architecture',
        name: 'architecture',
        description: 'Layout and layers.',
        enabled: true,
      ),
      ProjectRule(
        id: 'rule:builtin:widgets',
        name: 'widgets',
        description: 'Widget conventions.',
        enabled: false,
      ),
    ]);
  });

  test(
    'write puts each rule in docs/rules without frontmatter and updates AGENTS.md and CLAUDE.md',
    () async {
      File(p.join(project.path, 'CLAUDE.md')).writeAsStringSync('# Ours\n');
      final rules = await repository.builtinRules();

      await repository.write(project.path, rules);

      expect(read('docs/rules/architecture.md'), '# Arch\n');
      expect(read('docs/rules/widgets.md'), '# Widgets\n');
      expect(read('AGENTS.md'), contains('- `docs/rules/architecture.md` — Layout and layers.'));
      expect(read('CLAUDE.md'), '# Ours\n\n@AGENTS.md\n');
    },
  );

  test('hasRules is true once docs/rules exists', () async {
    expect(await repository.hasRules(project.path), isFalse);

    await repository.write(project.path, (await repository.builtinRules()).take(1).toList());

    expect(await repository.hasRules(project.path), isTrue);
  });

  test('a read-only folder throws', () async {
    await Process.run('chmod', <String>['555', project.path]);
    addTearDown(() => Process.runSync('chmod', <String>['755', project.path]));

    await expectLater(
      repository.write(project.path, await repository.builtinRules()),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('an AGENTS.md that cannot be written leaves no docs/rules', () async {
    final agents = File(p.join(project.path, 'AGENTS.md'))..writeAsStringSync('# Ours\n');
    await Process.run('chmod', <String>['444', agents.path]);
    addTearDown(() => Process.runSync('chmod', <String>['644', agents.path]));

    await expectLater(
      repository.write(project.path, await repository.builtinRules()),
      throwsA(isA<FileSystemException>()),
    );

    expect(Directory(p.join(project.path, 'docs', 'rules')).existsSync(), isFalse);
    expect(await repository.hasRules(project.path), isFalse);
  });

  test('a CLAUDE.md that links to AGENTS.md gets no import of itself', () async {
    File(p.join(project.path, 'AGENTS.md')).writeAsStringSync('# Shared\n');
    Link(p.join(project.path, 'CLAUDE.md')).createSync('AGENTS.md');

    await repository.write(project.path, await repository.builtinRules());

    expect(read('AGENTS.md'), isNot(contains('@AGENTS.md')));
    expect(read('AGENTS.md'), contains('<!-- flutter_code_agent:rules -->'));
  });

  test('a project folder that is gone is not created', () async {
    final gone = p.join(project.path, 'gone');

    await expectLater(
      repository.write(gone, await repository.builtinRules()),
      throwsA(isA<FileSystemException>()),
    );

    expect(Directory(gone).existsSync(), isFalse);
    expect(await repository.canHaveRules(gone), isFalse);
    expect(await repository.canHaveRules(project.path), isTrue);
  });

  test('markOffered remembers the project', () async {
    await repository.markOffered(7);

    expect(projects.offered, <int>[7]);
  });
}

final class _RecordingProjects implements IProjectsRepository {
  final List<int> offered = <int>[];

  @override
  Future<void> markRulesOffered(int projectId) async => offered.add(projectId);

  @override
  Stream<List<Project>> watchProjects() => const Stream<List<Project>>.empty();

  @override
  Future<void> remove(int projectId) async {}

  @override
  Future<void> reveal(String path) async {}

  @override
  Future<void> openPath(String path) async {}
}
