import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/project_removal_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late AppDatabase database;
  late ProjectsRepositoryImpl repository;
  late int project;
  late int chat;

  setUp(() async {
    dependencies = testDependencies();
    database = dependencies.database;
    repository = ProjectsRepositoryImpl(database: database, hub: dependencies.agentHub);
    project = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: '/work/avera-hotel', name: 'avera-hotel'));
    chat = await database
        .into(database.sessionsTable)
        .insert(SessionsTableCompanion.insert(projectId: project, agentId: 'claude'));
  });

  tearDown(() async {
    await dependencies.agentHub.dispose();
    await database.close();
  });

  Future<int> projectCount() async => (await database.select(database.projectsTable).get()).length;

  Future<int> chatCount() async => (await database.select(database.sessionsTable).get()).length;

  group('ProjectsRepositoryImpl.remove', () {
    test('deletes an idle project with its chats', () async {
      final live = await dependencies.agentHub.session(chat);
      live.status.value = SessionStatus.idle;

      await repository.remove(project);

      expect(await projectCount(), 0);
      expect(await chatCount(), 0);
    });

    test('deletes a project whose chats were never opened', () async {
      await repository.remove(project);
      expect(await projectCount(), 0);
    });

    for (final status in <SessionStatus>[
      SessionStatus.running,
      SessionStatus.awaitingPermission,
      SessionStatus.starting,
      SessionStatus.cancelling,
    ]) {
      test('refuses while a chat is $status and deletes nothing', () async {
        final live = await dependencies.agentHub.session(chat);
        live.status.value = status;

        await expectLater(repository.remove(project), throwsA(isA<ProjectBusyException>()));

        expect(await projectCount(), 1);
        expect(await chatCount(), 1);
      });
    }

    test('ignores busy chats of other projects', () async {
      final other = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/work/shop', name: 'shop'));
      final otherChat = await database
          .into(database.sessionsTable)
          .insert(SessionsTableCompanion.insert(projectId: other, agentId: 'claude'));
      (await dependencies.agentHub.session(otherChat)).status.value = SessionStatus.running;

      await repository.remove(project);

      expect(await projectCount(), 1);
      expect(await chatCount(), 1);
    });
  });

  group('ProjectRemovalController', () {
    test('completes with the removed project', () async {
      final controller = ProjectRemovalController(repository: repository)..remove(project);
      await pumpEventQueue();

      expect(controller.state, ProjectRemovalState.completed(project));
      expect(await projectCount(), 0);
      controller.dispose();
    });

    test('is busy while an agent of the project works', () async {
      (await dependencies.agentHub.session(chat)).status.value = SessionStatus.running;
      final controller = ProjectRemovalController(repository: repository)..remove(project);
      await pumpEventQueue();

      expect(controller.state, const ProjectRemovalState.busy());
      expect(await projectCount(), 1);
      controller.dispose();
    });
  });
}
