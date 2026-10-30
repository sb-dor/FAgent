import 'package:flutter_code_agent/src/feature/skills/controller/skill_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_library_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_text_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_exceptions.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/skills/models/skill_library.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_skills_repository.dart';

MemorySkillsRepository _repository() => MemorySkillsRepository(
  items: [memorySkill('architecture'), memoryRule('style')],
  projectItems: {
    '/a': [memorySkill('local', source: SkillSource.project)],
  },
  texts: {
    'skill:builtin:architecture': '# Architecture',
    'rule:builtin:style': 'Be brief',
    'skill:project:local': '# Local',
  },
);

void main() {
  group('SkillLibraryController', () {
    late MemorySkillsRepository repository;
    late SkillLibraryController controller;

    setUp(() {
      repository = _repository();
      controller = SkillLibraryController(repository: repository);
    });

    tearDown(() async {
      controller.dispose();
      await pumpEventQueue();
    });

    test('starts idle with an empty library', () {
      expect(controller.state, isA<SkillLibrary$IdleState>());
      expect(controller.library, SkillLibrary.empty);
    });

    test('watch emits loaded for the project and switches projects', () async {
      controller.watch(projectId: 1, projectRoot: '/a');
      await pumpEventQueue();

      var state = controller.state as SkillLibrary$LoadedState;
      expect(state.projectId, 1);
      expect(state.library.skills.map((item) => item.name), ['architecture', 'local']);
      expect(controller.library, state.library);
      expect(repository.cancels, 0);

      controller.watch(projectId: 2, projectRoot: '/b');
      await pumpEventQueue();

      expect(repository.cancels, 1);
      expect(repository.activeWatchers, 1);
      state = controller.state as SkillLibrary$LoadedState;
      expect(state.projectId, 2);
      expect(state.library.skills.map((item) => item.name), ['architecture']);
    });

    test('watching the same project again does nothing', () async {
      controller.watch(projectId: 1, projectRoot: '/a');
      await pumpEventQueue();
      controller.watch(projectId: 1, projectRoot: '/a');
      await pumpEventQueue();

      expect(repository.cancels, 0);
      expect(repository.calls.where((call) => call.startsWith('watch')), hasLength(1));
    });

    test('is loading until the first library arrives', () async {
      controller.watch(projectId: 1);
      expect(controller.state, isA<SkillLibrary$LoadingState>());
      await pumpEventQueue();
      expect(controller.state, isA<SkillLibrary$LoadedState>());
    });

    test('follows changes of the repository', () async {
      controller.watch(projectId: 1);
      await pumpEventQueue();

      await repository.setEnabled('skill:builtin:architecture', enabled: false);
      await pumpEventQueue();

      expect(controller.library.byId('skill:builtin:architecture')!.enabled, isFalse);
    });

    test('a failing stream ends in failed and keeps the last library', () async {
      controller.watch(projectId: 1);
      await pumpEventQueue();
      final before = controller.library;

      repository.addWatchError(StateError('disk'));
      await pumpEventQueue();

      final state = controller.state as SkillLibrary$FailedState;
      expect(state.error, isA<StateError>());
      expect(state.projectId, 1);
      expect(controller.library, before);

      // The repository keeps watching, so a later change recovers.
      await repository.setEnabled('rule:builtin:style', enabled: false);
      await pumpEventQueue();
      expect(controller.state, isA<SkillLibrary$LoadedState>());
    });

    test('dispose cancels the subscription', () async {
      final other = SkillLibraryController(repository: repository)..watch(projectId: 1);
      await pumpEventQueue();

      other.dispose();
      await pumpEventQueue();

      expect(repository.cancels, 1);
      expect(repository.activeWatchers, 0);
    });
  });

  group('SkillActionsController', () {
    late MemorySkillsRepository repository;
    late SkillActionsController controller;

    setUp(() {
      repository = _repository();
      controller = SkillActionsController(repository: repository);
    });

    tearDown(() async {
      controller.dispose();
      await pumpEventQueue();
    });

    test('setEnabled and clearException go to the repository', () async {
      expect(controller.state, isA<SkillActions$IdleState>());

      controller.setEnabled('skill:builtin:architecture', enabled: false, projectId: 1);
      expect(controller.state, isA<SkillActions$ProcessingState>());
      await pumpEventQueue();
      expect(controller.state, const SkillActionsState.completed());

      controller.clearException('skill:builtin:architecture', 1);
      await pumpEventQueue();

      expect(repository.calls, [
        'setEnabled skill:builtin:architecture false project=1',
        'clearException skill:builtin:architecture project=1',
      ]);
    });

    test('a global switch of a project item fails', () async {
      controller.setEnabled('skill:project:local', enabled: false);
      await pumpEventQueue();

      expect((controller.state as SkillActions$FailedState).error, isA<ArgumentError>());
    });

    test('create completes with the new id', () async {
      controller.create(KnowledgeKind.skill, 'my-skill');
      await pumpEventQueue();

      expect(controller.state, const SkillActionsState.completed(id: 'skill:user:my-skill'));
    });

    test('a taken name fails with KnowledgeExistsException', () async {
      controller.create(KnowledgeKind.skill, 'my-skill');
      await pumpEventQueue();
      controller.create(KnowledgeKind.skill, 'my-skill');
      await pumpEventQueue();

      expect((controller.state as SkillActions$FailedState).error, isA<KnowledgeExistsException>());
    });

    test('a bad name fails with InvalidKnowledgeNameException', () async {
      controller.create(KnowledgeKind.rule, 'Bad Name');
      await pumpEventQueue();

      expect(
        (controller.state as SkillActions$FailedState).error,
        isA<InvalidKnowledgeNameException>(),
      );
    });

    test('save writes the text, a built-in item is refused', () async {
      controller.save('skill:project:local', '# New', projectRoot: '/a');
      await pumpEventQueue();
      expect(controller.state, const SkillActionsState.completed());
      expect(await repository.read('skill:project:local', projectRoot: '/a'), '# New');

      controller.save('skill:builtin:architecture', 'x');
      await pumpEventQueue();
      expect(
        (controller.state as SkillActions$FailedState).error,
        isA<ReadOnlyKnowledgeException>(),
      );
    });

    test('duplicate completes with the id of the copy', () async {
      controller.duplicate('skill:builtin:architecture');
      await pumpEventQueue();
      expect(controller.state, const SkillActionsState.completed(id: 'skill:user:architecture'));

      controller.duplicate('skill:project:local', projectRoot: '/a');
      await pumpEventQueue();
      expect(controller.state, const SkillActionsState.completed(id: 'skill:user:local'));
    });

    test('duplicate of a project item without its root fails', () async {
      controller.duplicate('skill:project:local');
      await pumpEventQueue();

      expect(
        (controller.state as SkillActions$FailedState).error,
        isA<KnowledgeNotFoundException>(),
      );
    });

    test('importFolder completes with the new id', () async {
      final imported = MemorySkillsRepository(
        importable: {'/tmp/ideas': '---\nname: ideas\n---\n'},
      );
      final actions = SkillActionsController(repository: imported);
      addTearDown(actions.dispose);

      actions.importFolder('/tmp/ideas');
      await pumpEventQueue();
      expect(actions.state, const SkillActionsState.completed(id: 'skill:user:ideas'));

      actions.importFolder('/tmp/empty');
      await pumpEventQueue();
      expect((actions.state as SkillActions$FailedState).error, isA<InvalidKnowledgeException>());
    });

    test('drops a second action while one is processing', () async {
      controller
        ..create(KnowledgeKind.skill, 'one')
        ..create(KnowledgeKind.skill, 'two');
      await pumpEventQueue();

      expect(repository.calls, ['create skill one']);
    });
  });

  group('SkillTextController', () {
    late MemorySkillsRepository repository;
    late SkillTextController controller;

    setUp(() {
      repository = _repository();
      controller = SkillTextController(repository: repository);
    });

    tearDown(() async {
      controller.dispose();
      await pumpEventQueue();
    });

    test('text load', () async {
      expect(controller.state, isA<SkillText$IdleState>());

      controller.load('rule:builtin:style');
      expect(controller.state, const SkillTextState.loading('rule:builtin:style'));
      await pumpEventQueue();

      expect(controller.state, const SkillTextState.loaded('rule:builtin:style', 'Be brief'));
    });

    test('a project item is read from its root', () async {
      controller.load('skill:project:local', projectRoot: '/a');
      await pumpEventQueue();

      expect(controller.state, const SkillTextState.loaded('skill:project:local', '# Local'));
    });

    test('a missing item fails with its id', () async {
      controller.load('skill:builtin:nothing');
      await pumpEventQueue();

      final state = controller.state as SkillText$FailedState;
      expect(state.id, 'skill:builtin:nothing');
      expect(state.error, isA<KnowledgeNotFoundException>());
    });

    test('the last load wins', () async {
      controller
        ..load('skill:builtin:architecture')
        ..load('rule:builtin:style');
      await pumpEventQueue();

      expect(controller.state, const SkillTextState.loaded('rule:builtin:style', 'Be brief'));
    });
  });
}
