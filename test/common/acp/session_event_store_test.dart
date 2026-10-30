import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/acp/session_event_store.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late int sessionId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final project = await database
        .into(database.projectsTable)
        .insert(ProjectsTableCompanion.insert(path: '/p', name: 'p'));
    sessionId = await database
        .into(database.sessionsTable)
        .insert(SessionsTableCompanion.insert(projectId: project, agentId: 'claude'));
  });

  tearDown(() => database.close());

  Future<List<int>> storedSeqs() async =>
      (await database.select(database.sessionEventsTable).get()).map((r) => r.seq).toList();

  test('agent frames are visible at once and written in a batch', () async {
    final store = await SessionEventStore.open(
      database,
      sessionId,
      flushInterval: const Duration(milliseconds: 50),
    );
    store
      ..addAgentFrame('agent_message_chunk', <String, Object?>{'n': 0})
      ..addAgentFrame('agent_message_chunk', <String, Object?>{'n': 1});

    expect(store.events.map((e) => e.seq), <int>[0, 1]);
    expect(await storedSeqs(), isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(await storedSeqs(), <int>[0, 1]);
    await store.close();
  });

  test('a durable event writes everything queued before it first', () async {
    final store = await SessionEventStore.open(
      database,
      sessionId,
      flushInterval: const Duration(hours: 1),
    );
    store.addAgentFrame('tool_call', <String, Object?>{});
    final durable = await store.addDurable(
      SessionEventOrigin.app,
      SessionEventKind.permissionRequest,
      <String, Object?>{'requestId': '7'},
    );

    expect(durable.seq, 1);
    expect(await storedSeqs(), <int>[0, 1]);
    await store.close();
  });

  test('a reopened store continues the sequence and replays the journal', () async {
    final first = await SessionEventStore.open(database, sessionId);
    await first.addDurable(SessionEventOrigin.user, SessionEventKind.prompt, <String, Object?>{
      'text': 'hi',
    });
    first.addAgentFrame('agent_message_chunk', <String, Object?>{'text': 'hello'});
    await first.close();

    final second = await SessionEventStore.open(database, sessionId);
    expect(second.events.map((e) => (e.seq, e.kind)), <(int, String)>[
      (0, SessionEventKind.prompt),
      (1, 'agent_message_chunk'),
    ]);
    expect(second.events.first.payload, <String, Object?>{'text': 'hi'});
    final next = await second.addDurable(
      SessionEventOrigin.app,
      SessionEventKind.system,
      <String, Object?>{},
    );
    expect(next.seq, 2);
    await second.close();
  });

  test('a failed durable write throws and the event is never shown', () async {
    // No session 999: the foreign key makes the write fail.
    final store = await SessionEventStore.open(database, 999);
    await expectLater(
      store.addDurable(SessionEventOrigin.user, SessionEventKind.prompt, <String, Object?>{}),
      throwsA(isA<Object>()),
    );
    expect(store.events, isEmpty);
  });

  test('frames from a failed batch are retried with the next write', () async {
    final store = await SessionEventStore.open(
      database,
      sessionId,
      flushInterval: const Duration(hours: 1),
    );
    store.addAgentFrame('agent_message_chunk', <String, Object?>{});
    // Make the next write fail, then let it succeed.
    await database.customStatement('PRAGMA query_only = ON');
    await expectLater(store.flush(), throwsA(isA<Object>()));
    await database.customStatement('PRAGMA query_only = OFF');

    await store.flush();

    expect(await storedSeqs(), <int>[0]);
    await store.close();
  });

  test('listeners get events in visibility order with their seq', () async {
    final store = await SessionEventStore.open(
      database,
      sessionId,
      flushInterval: const Duration(hours: 1),
    );
    final seen = <int>[];
    store.added.listen((e) => seen.add(e.seq));

    final durable = store.addDurable(
      SessionEventOrigin.app,
      SessionEventKind.system,
      <String, Object?>{},
    );
    store.addAgentFrame('agent_message_chunk', <String, Object?>{});
    await durable;

    // The frame (seq 1) is visible before the durable event (seq 0) commits.
    expect(seen, <int>[1, 0]);
    expect(store.events.map((e) => e.seq), <int>[0, 1]);
    await store.close();
  });

  test('a durable event after a failed batch is written after the retried frames', () async {
    final store = await SessionEventStore.open(
      database,
      sessionId,
      flushInterval: const Duration(hours: 1),
    );
    store.addAgentFrame('agent_message_chunk', <String, Object?>{});
    await database.customStatement('PRAGMA query_only = ON');
    await expectLater(store.flush(), throwsA(isA<Object>()));
    await database.customStatement('PRAGMA query_only = OFF');

    await store.addDurable(SessionEventOrigin.app, SessionEventKind.system, <String, Object?>{});

    expect(await storedSeqs(), <int>[0, 1]);
    await store.close();
  });
}
