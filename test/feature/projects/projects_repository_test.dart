import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_queue_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/data/projects_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('markRulesOffered sets rulesOffered', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final id = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: '/work/app', name: 'app'));
    final repository = ProjectsRepositoryImpl(
      database: database,
      hub: AgentHub(database: database, environment: const ShellEnvironment(<String, String>{})),
      queuedChats: ChatQueueRegistry(create: (_) => throw UnimplementedError()),
    );

    expect((await repository.watchProjects().first).single.rulesOffered, isFalse);
    await repository.markRulesOffered(id);

    expect((await repository.watchProjects().first).single.rulesOffered, isTrue);
  });
}
