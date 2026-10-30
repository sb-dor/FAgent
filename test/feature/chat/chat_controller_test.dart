import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_event_store.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeChatRepository implements IChatRepository {
  _FakeChatRepository(this.session);

  final LiveSession session;

  @override
  Future<LiveSession> open(int sessionId) async => session;

  @override
  Set<String> openPermissionIds(int sessionId) => const <String>{};

  @override
  Future<void> retry(int sessionId) async {}

  @override
  Future<void> startNewAgentSession(int sessionId) async {}

  @override
  List<String> loginMethods(String agentId) => const <String>[];

  @override
  Future<bool> login(
    String agentId,
    String methodId, {
    required void Function(List<String> lines) onOutput,
  }) async => true;
}

void main() {
  late AppDatabase database;
  late LiveSession session;
  late ChatController controller;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    session = LiveSession(
      id: 1,
      agentId: 'claude',
      cwd: '/tmp',
      store: await SessionEventStore.open(database, 1),
    );
    controller = ChatController(
      repository: _FakeChatRepository(session),
      refoldInterval: Duration.zero,
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  ChatView view() => (controller.state as Chat$CompletedState).view;

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  Future<void> open() async {
    controller.open(1);
    await settle();
  }

  test('the view has the commands the agent announced', () async {
    session.availableCommands.value = <Map<String, Object?>>[
      <String, Object?>{'name': 'compact', 'description': 'Compact'},
    ];
    await open();
    expect(view().commands.map((c) => c.name), <String>['compact']);
  });

  test('new availableCommands update the view', () async {
    await open();
    expect(view().commands, isEmpty);

    session.availableCommands.value = <Map<String, Object?>>[
      <String, Object?>{'name': 'init'},
      <String, Object?>{'name': 5},
    ];
    await settle();

    expect(view().commands.map((c) => c.name), <String>['init']);
  });

  test('refolds without new commands keep the same list instance', () async {
    session.availableCommands.value = <Map<String, Object?>>[
      <String, Object?>{'name': 'compact'},
    ];
    await open();
    final before = view().commands;

    session.status.value = session.status.value; // no change
    session.canForceStop.value = true;
    await settle();

    expect(view().canForceStop, isTrue);
    expect(identical(view().commands, before), isTrue);
  });
}
