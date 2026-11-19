import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AgentHub.session` shares one open per chat between callers that run in different error
/// zones (the handlers of different controllers).
void main() {
  late AppDatabase database;
  late AgentHub hub;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    hub = AgentHub(
      database: database,
      environment: const ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'}),
    );
  });

  tearDown(() async {
    await hub.dispose();
    await database.close();
  });

  /// Awaits `hub.session(id)` in a zone of its own; completes with what that zone saw.
  Future<({Object? caught, List<Object> uncaught})> inOwnZone(int id) {
    final done = Completer<({Object? caught, List<Object> uncaught})>();
    final uncaught = <Object>[];
    runZonedGuarded(() async {
      Object? caught;
      try {
        // An error kept in another zone never reaches this caller.
        await hub.session(id).timeout(const Duration(seconds: 2));
      } on Object catch (error) {
        caught = error;
      }
      // Lets an error that leaked into the zone arrive before the zone reports.
      await pumpEventQueue();
      done.complete((caught: caught, uncaught: uncaught));
    }, (error, stackTrace) => uncaught.add(error));
    return done.future;
  }

  test('two callers in different zones each get the failed open in their own zone', () async {
    final first = inOwnZone(404);
    final second = inOwnZone(404);

    final results = await Future.wait(<Future<({Object? caught, List<Object> uncaught})>>[
      first,
      second,
    ]);

    for (final result in results) {
      expect(result.caught, isA<StateError>());
      expect(result.uncaught, isEmpty);
    }
  });

  test('the open is shared, and a failed one is tried again by the next caller', () async {
    final projectId = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: '/tmp', name: 'p'));
    final chat = await database
        .into(database.sessionsTable)
        .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'claude'));

    final sessions = await Future.wait(<Future<LiveSession>>[hub.session(chat), hub.session(chat)]);
    expect(identical(sessions.first, sessions.last), isTrue);

    await expectLater(hub.session(chat + 1), throwsStateError);
    await database
        .into(database.sessionsTable)
        .insert(SessionsTableCompanion.insert(projectId: projectId, agentId: 'claude'));
    expect((await hub.session(chat + 1)).id, chat + 1);
  });
}
