import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/skills/data/builtin_knowledge.dart';
import 'package:flutter_code_agent/src/feature/skills/data/frontmatter.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_exceptions.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:flutter_test/flutter_test.dart';

final class _MapKnowledge implements IBuiltinKnowledge {
  const _MapKnowledge(this.files);

  final Map<String, String> files;

  @override
  Future<Map<String, String>> load() async => files;
}

String _doc(String name, {String? description}) =>
    writeFrontmatter({'name': name, 'description': description ?? 'does $name'}, '# $name\n');

/// Collects what [stream] emits and waits for a library that satisfies a condition.
final class _Listener {
  _Listener(Stream<SkillLibrary> stream) {
    _subscription = stream.listen(libraries.add);
  }

  final List<SkillLibrary> libraries = [];
  late final StreamSubscription<SkillLibrary> _subscription;

  Future<SkillLibrary> until(bool Function(SkillLibrary library) test) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (DateTime.now().isBefore(deadline)) {
      for (final library in libraries) {
        if (test(library)) return library;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('No library satisfied the condition within a second');
  }

  Future<void> cancel() => _subscription.cancel();
}

void main() {
  late Directory temp;
  late Directory user;
  late Directory project;
  late AppDatabase database;
  late SkillsRepositoryImpl repository;

  File userFile(String relative) => File('${user.path}/$relative');

  Future<void> put(File file, String text) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<void> addProject(int id) => database
      .into(database.projectsTable)
      .insert(ProjectsTableCompanion.insert(path: '/work/p$id', name: 'p$id'));

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('skills_repository_test');
    user = Directory('${temp.path}/user')..createSync();
    project = Directory('${temp.path}/project')..createSync();
    database = AppDatabase(NativeDatabase.memory());
    repository = SkillsRepositoryImpl(
      database: database,
      builtin: _MapKnowledge({
        'skills/a/SKILL.md': _doc('a'),
        'skills/a/templates/t.dart': '// t',
        'rules/r.md': _doc('r'),
      }),
      userRoot: user.path,
      pollInterval: const Duration(milliseconds: 20),
    );
    await addProject(1);
    await addProject(2);
  });

  tearDown(() async {
    await database.close();
    temp.deleteSync(recursive: true);
  });

  Future<SkillLibrary> first({int? projectId, String? projectRoot}) =>
      repository.watch(projectId: projectId, projectRoot: projectRoot).first;

  test('lists built-in, user and project items in source order', () async {
    await put(userFile('skills/b/SKILL.md'), _doc('b'));
    await put(File('${project.path}/.claude/skills/c/SKILL.md'), _doc('c'));
    await put(File('${project.path}/.claude/rules/p.md'), _doc('p'));

    final library = await first(projectRoot: project.path);

    expect(library.skills.map((s) => s.id), ['skill:builtin:a', 'skill:user:b', 'skill:project:c']);
    expect(library.rules.map((r) => r.id), ['rule:builtin:r', 'rule:project:p']);
    expect(library.byId('skill:builtin:a')!.readOnly, isTrue);
    expect(library.byId('skill:builtin:a')!.files, ['SKILL.md', 'templates/t.dart']);
    expect(library.byId('skill:user:b')!.readOnly, isFalse);
    expect(library.byId('skill:project:c')!.readOnly, isFalse);
    expect(library.byId('rule:project:p')!.readOnly, isFalse);
    expect(library.byId('skill:user:b')!.description, 'does b');
  });

  test('lists skill files with SKILL.md first, sorted, without hidden ones', () async {
    await put(userFile('skills/b/SKILL.md'), _doc('b'));
    await put(userFile('skills/b/z.md'), 'z');
    await put(userFile('skills/b/docs/a.md'), 'a');
    await put(userFile('skills/b/.hidden'), 'h');

    final library = await first();

    expect(library.byId('skill:user:b')!.files, ['SKILL.md', 'docs/a.md', 'z.md']);
  });

  test('a folder without SKILL.md is skipped, a broken one shows its problem', () async {
    await Directory('${user.path}/skills/empty').create(recursive: true);
    await put(userFile('skills/bad/SKILL.md'), 'no frontmatter');
    await put(userFile('skills/nodesc/SKILL.md'), '---\nname: nodesc\n---\n');
    await put(userFile('skills/yaml/SKILL.md'), '---\nname: [a\n---\n');

    final library = await first();

    expect(library.byId('skill:user:empty'), isNull);
    final bad = library.byId('skill:user:bad')!;
    expect(bad.title, 'bad');
    expect(bad.problem, 'No frontmatter');
    expect(library.byId('skill:user:nodesc')!.problem, 'No description');
    expect(library.byId('skill:user:yaml')!.problem, isNotNull);
  });

  test('a skill created on disk while watching appears', () async {
    final root = '${temp.path}/later';
    final listener = _Listener(repository.watch(projectRoot: root));
    addTearDown(listener.cancel);

    final initial = await listener.until((_) => true);
    expect(initial.byId('skill:project:new'), isNull);

    await put(File('$root/.claude/skills/new/SKILL.md'), _doc('new'));

    final next = await listener.until((library) => library.byId('skill:project:new') != null);
    expect(next.byId('skill:project:new')!.source, SkillSource.project);
  });

  test('emits again only when files change', () async {
    await put(userFile('skills/b/SKILL.md'), _doc('b'));
    final emitted = <SkillLibrary>[];
    final subscription = repository.watch().listen(emitted.add);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(emitted, hasLength(1));

    await put(userFile('skills/b/SKILL.md'), _doc('b', description: 'changed'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await subscription.cancel();

    expect(emitted, hasLength(2));
    expect(emitted.last.byId('skill:user:b')!.description, 'changed');
  });

  test('enabled by default; a project exception', () async {
    await repository.setEnabled('skill:builtin:a', enabled: false, projectId: 1);

    final one = (await first(projectId: 1)).byId('skill:builtin:a')!;
    expect(one.enabled, isFalse);
    expect(one.enabledGlobally, isTrue);
    expect(one.exceptions, {1});

    final two = (await first(projectId: 2)).byId('skill:builtin:a')!;
    expect(two.enabled, isTrue);
  });

  test('flipping global drops exceptions that now match', () async {
    await repository.setEnabled('skill:builtin:a', enabled: false, projectId: 1);
    await repository.setEnabled('skill:builtin:a', enabled: false);

    var item = (await first(projectId: 1)).byId('skill:builtin:a')!;
    expect(item.enabledGlobally, isFalse);
    expect(item.enabled, isFalse);
    expect(item.exceptions, isEmpty);

    await repository.setEnabled('skill:builtin:a', enabled: true, projectId: 2);
    item = (await first(projectId: 2)).byId('skill:builtin:a')!;
    expect(item.enabled, isTrue);
    expect(item.exceptions, {2});

    await repository.setEnabled('skill:builtin:a', enabled: false);
    await repository.setEnabled('skill:builtin:a', enabled: false, projectId: 2);
    expect(await database.select(database.skillStatesTable).get(), hasLength(1));
  });

  test('setting a project value equal to the global one leaves no row', () async {
    await repository.setEnabled('skill:builtin:a', enabled: true, projectId: 1);

    expect(
      (await database.select(database.skillStatesTable).get()).where((r) => r.projectId == 1),
      isEmpty,
    );
  });

  test('clearException removes the project row', () async {
    await repository.setEnabled('skill:builtin:a', enabled: false, projectId: 1);
    await repository.clearException('skill:builtin:a', 1);

    final item = (await first(projectId: 1)).byId('skill:builtin:a')!;
    expect(item.enabled, isTrue);
    expect(item.exceptions, isEmpty);
  });

  test('watching reacts to skill_states changes', () async {
    final listener = _Listener(repository.watch(projectId: 1));
    addTearDown(listener.cancel);
    await listener.until((_) => true);

    await repository.setEnabled('skill:builtin:a', enabled: false, projectId: 1);

    final next = await listener.until((library) => !library.byId('skill:builtin:a')!.enabled);
    expect(next.byId('skill:builtin:a')!.exceptions, {1});
  });

  test('write to built-in throws, write to user saves', () async {
    await put(userFile('skills/b/SKILL.md'), _doc('b'));
    await put(userFile('rules/x.md'), _doc('x'));

    await expectLater(
      repository.write('skill:builtin:a', 'x'),
      throwsA(isA<ReadOnlyKnowledgeException>()),
    );
    await repository.write('skill:user:b', 'new text');
    await repository.write('rule:user:x', 'rule text');

    expect(await repository.read('skill:user:b'), 'new text');
    expect(await repository.read('rule:user:x'), 'rule text');
    expect(await repository.read('skill:builtin:a'), _doc('a'));
    expect(await repository.read('rule:builtin:r'), _doc('r'));
    await expectLater(
      repository.read('skill:user:missing'),
      throwsA(isA<KnowledgeNotFoundException>()),
    );
  });

  test('create writes the template and rejects bad and taken names', () async {
    await put(userFile('skills/b/SKILL.md'), 'keep');

    await expectLater(
      repository.create(KnowledgeKind.skill, 'Bad Name'),
      throwsA(isA<InvalidKnowledgeNameException>()),
    );
    await expectLater(
      repository.create(KnowledgeKind.skill, 'b'),
      throwsA(isA<KnowledgeExistsException>()),
    );
    expect(await userFile('skills/b/SKILL.md').readAsString(), 'keep');

    expect(await repository.create(KnowledgeKind.skill, 'fresh'), 'skill:user:fresh');
    expect(await repository.create(KnowledgeKind.rule, 'law'), 'rule:user:law');
    final parsed = parseFrontmatter(await userFile('skills/fresh/SKILL.md').readAsString())!;
    expect(parsed.fields, {'name': 'fresh', 'description': ''});
    expect(parsed.body, '# fresh\n');
    expect(userFile('rules/law.md').existsSync(), isTrue);
    await expectLater(
      repository.create(KnowledgeKind.rule, 'law'),
      throwsA(isA<KnowledgeExistsException>()),
    );
  });

  test('duplicate picks a free name and renames frontmatter', () async {
    expect(await repository.duplicate('skill:builtin:a'), 'skill:user:a');
    expect(await repository.duplicate('skill:builtin:a'), 'skill:user:a-copy');
    expect(await repository.duplicate('skill:builtin:a'), 'skill:user:a-copy-2');

    final copy = parseFrontmatter(await userFile('skills/a-copy/SKILL.md').readAsString())!;
    expect(copy.fields['name'], 'a-copy');
    expect(
      parseFrontmatter(await userFile('skills/a/SKILL.md').readAsString())!.fields['name'],
      'a',
    );
    expect(await userFile('skills/a-copy/templates/t.dart').readAsString(), '// t');

    expect(await repository.duplicate('rule:builtin:r'), 'rule:user:r');
    expect(userFile('rules/r.md').existsSync(), isTrue);
  });

  test('duplicate of a user skill keeps other frontmatter fields', () async {
    await put(
      userFile('skills/b/SKILL.md'),
      '---\nname: b\ndescription: "x: y"\nmetadata:\n  version: 2\n---\nBody\n',
    );
    await put(userFile('skills/b/extra/notes.md'), 'notes');

    final id = await repository.duplicate('skill:user:b');

    expect(id, 'skill:user:b-copy');
    expect(
      await userFile('skills/b-copy/SKILL.md').readAsString(),
      '---\nname: b-copy\ndescription: "x: y"\nmetadata:\n  version: 2\n---\nBody\n',
    );
    expect(await userFile('skills/b-copy/extra/notes.md').readAsString(), 'notes');
  });

  test('importFolder copies a skill and refuses a folder without SKILL.md', () async {
    final source = Directory('${temp.path}/outside/imported')..createSync(recursive: true);
    await File('${source.path}/SKILL.md').writeAsString(_doc('imported'));
    await File('${source.path}/data.txt').writeAsString('data');
    final empty = Directory('${temp.path}/outside/empty')..createSync();

    expect(await repository.importFolder(source.path), 'skill:user:imported');
    expect(await userFile('skills/imported/data.txt').readAsString(), 'data');
    expect(await repository.importFolder(source.path), 'skill:user:imported-copy');
    final copy = parseFrontmatter(await userFile('skills/imported-copy/SKILL.md').readAsString())!;
    expect(copy.fields['name'], 'imported-copy');

    await expectLater(
      repository.importFolder(empty.path),
      throwsA(isA<InvalidKnowledgeException>()),
    );
  });

  test('mutations show up in an open watch without waiting for a poll', () async {
    final slow = SkillsRepositoryImpl(
      database: database,
      builtin: const _MapKnowledge({}),
      userRoot: user.path,
      pollInterval: const Duration(minutes: 5),
    );
    final listener = _Listener(slow.watch());
    addTearDown(listener.cancel);
    await listener.until((_) => true);

    await slow.create(KnowledgeKind.skill, 'quick');

    final next = await listener.until((library) => library.byId('skill:user:quick') != null);
    expect(next.skills, hasLength(1));
  });

  test('the stream closes on cancel', () async {
    final subscription = repository.watch().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(repository.activeWatchers, 1);

    await subscription.cancel();
    await put(userFile('skills/late/SKILL.md'), _doc('late'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(repository.activeWatchers, 0);
  });

  group('project items', () {
    late Directory other;

    setUp(() {
      other = Directory('${temp.path}/other')..createSync();
    });

    File skillIn(Directory root) => File('${root.path}/.claude/skills/foo/SKILL.md');

    test('read, write and duplicate work with the given project root', () async {
      await put(skillIn(project), _doc('foo'));
      await put(File('${project.path}/.claude/skills/foo/extra.md'), 'extra');

      await repository.write('skill:project:foo', 'edited', projectRoot: project.path);
      expect(await repository.read('skill:project:foo', projectRoot: project.path), 'edited');
      expect(await skillIn(project).readAsString(), 'edited');

      final id = await repository.duplicate('skill:project:foo', projectRoot: project.path);
      expect(id, 'skill:user:foo');
      expect(await userFile('skills/foo/extra.md').readAsString(), 'extra');
    });

    test('a project id without a project root is not found', () async {
      await put(skillIn(project), _doc('foo'));

      await expectLater(
        repository.read('skill:project:foo'),
        throwsA(isA<KnowledgeNotFoundException>()),
      );
      await expectLater(
        repository.write('skill:project:foo', 'x'),
        throwsA(isA<KnowledgeNotFoundException>()),
      );
      await expectLater(
        repository.duplicate('skill:project:foo'),
        throwsA(isA<KnowledgeNotFoundException>()),
      );
      expect(await skillIn(project).readAsString(), _doc('foo'));
    });

    test('with two watches open, a write goes only to the project it names', () async {
      await put(skillIn(project), _doc('foo'));
      await put(skillIn(other), _doc('foo', description: 'other'));
      final first = _Listener(repository.watch(projectRoot: project.path));
      final second = _Listener(repository.watch(projectRoot: other.path));
      addTearDown(first.cancel);
      addTearDown(second.cancel);
      await first.until((_) => true);
      await second.until((_) => true);

      await repository.write('skill:project:foo', 'x', projectRoot: project.path);

      expect(await skillIn(project).readAsString(), 'x');
      expect(await skillIn(other).readAsString(), _doc('foo', description: 'other'));
      expect(await repository.read('skill:project:foo', projectRoot: other.path), isNot('x'));
    });

    test('a global switch of a project item is refused', () async {
      expect(() => repository.setEnabled('skill:project:foo', enabled: false), throwsArgumentError);
      await repository.setEnabled('skill:project:foo', enabled: false, projectId: 1);
      expect(await database.select(database.skillStatesTable).get(), hasLength(1));
    });
  });

  test('an unreadable subfolder does not hide the other skills', () async {
    await put(userFile('skills/a1/SKILL.md'), _doc('a1'));
    await put(userFile('skills/b2/SKILL.md'), _doc('b2'));
    await put(userFile('skills/b2/locked/file.txt'), 'x');
    await put(userFile('skills/c3/SKILL.md'), _doc('c3'));
    await put(userFile('skills/z9/SKILL.md'), _doc('z9'));
    final locked = Directory('${user.path}/skills/b2/locked');
    await Process.run('chmod', ['000', locked.path]);
    addTearDown(() => Process.run('chmod', ['755', locked.path]));

    final library = await first();

    expect(library.skills.where((s) => s.source == SkillSource.user).map((s) => s.name), [
      'a1',
      'b2',
      'c3',
      'z9',
    ]);
  });
}
