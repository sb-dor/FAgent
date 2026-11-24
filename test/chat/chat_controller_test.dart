import 'dart:async';
import 'dart:collection';

import 'package:flutter_code_agent/_core/acp/session_event.dart';
import 'package:flutter_code_agent/_core/acp/session_status.dart';
import 'package:flutter_code_agent/chat/controller/chat_controller.dart';
import 'package:flutter_code_agent/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/chat/models/chat_item.dart';
import 'package:flutter_code_agent/chat/models/chat_runtime.dart';
import 'package:flutter_code_agent/chat/models/chat_view.dart';
import 'package:flutter_code_agent/prompt_sending/models/slash_command.dart';
import 'package:flutter_code_agent/session_config/models/config_option.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hands the controller the runtimes the test adds; [watch] fails with [openError] when set.
final class _FakeChatRepository implements IChatRepository {
  final StreamController<ChatRuntime> runtimes = StreamController<ChatRuntime>.broadcast();
  Object? openError;
  int watched = 0;

  @override
  Stream<ChatRuntime> watch(int sessionId) {
    watched++;
    if (openError case final error?) return Stream<ChatRuntime>.error(error);
    return runtimes.stream;
  }

  Future<void> close() => runtimes.close();

  @override
  Stream<SessionStatus> watchStatus(int sessionId) => throw UnimplementedError();

  @override
  Future<void> retry(int sessionId) async {}

  @override
  Future<void> startNewAgentSession(int sessionId) async {}
}

ChatRuntime _runtime({
  List<SessionEvent> events = const <SessionEvent>[],
  SessionStatus status = SessionStatus.idle,
  bool canForceStop = false,
  List<SlashCommand> commands = const <SlashCommand>[],
}) => ChatRuntime(
  sessionId: 1,
  agentId: 'claude',
  events: events,
  openPermissionIds: const <String>{},
  status: status,
  problem: null,
  canForceStop: canForceStop,
  canRetryPrompt: false,
  configOptions: const <ConfigOption>[],
  bypassBlocked: false,
  preparingTurn: false,
  commands: commands,
);

SessionEvent _prompt(int seq, String text) => SessionEvent(
  seq: seq,
  origin: SessionEventOrigin.user,
  kind: SessionEventKind.prompt,
  payload: <String, Object?>{
    'prompt': <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': text},
    ],
  },
  createdAt: DateTime(2026),
);

void main() {
  late _FakeChatRepository repository;
  late ChatController controller;

  setUp(() {
    repository = _FakeChatRepository();
    controller = ChatController(
      repository: repository,
      refoldInterval: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    controller.dispose();
    await repository.close();
  });

  ChatView view() => (controller.state as Chat$CompletedState).view;

  Future<void> open() async {
    controller.open(1);
    await pumpEventQueue();
  }

  test('the chat shows as soon as its first runtime arrives', () async {
    await open();
    expect(controller.state, isA<Chat$InProgressState>());

    repository.runtimes.add(
      _runtime(
        events: <SessionEvent>[_prompt(1, 'hi')],
        commands: const <SlashCommand>[SlashCommand(name: 'compact', source: SlashSource.agent)],
      ),
    );
    await pumpEventQueue();

    expect(view().sessionId, 1);
    expect(view().agentId, 'claude');
    expect(view().items.whereType<UserMessageItem>().single.text, 'hi');
    expect(view().commands.map((c) => c.name), <String>['compact']);
  });

  test('later runtimes are folded once per interval, the last one wins', () async {
    await open();
    repository.runtimes.add(_runtime());
    await pumpEventQueue();

    repository.runtimes
      ..add(_runtime(events: <SessionEvent>[_prompt(1, 'one')], status: SessionStatus.running))
      ..add(
        _runtime(
          events: <SessionEvent>[_prompt(1, 'one'), _prompt(2, 'two')],
          status: SessionStatus.running,
          canForceStop: true,
        ),
      );
    await pumpEventQueue();
    // Not folded yet.
    expect(view().items, isEmpty);
    expect(view().status, SessionStatus.idle);

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(view().items.whereType<UserMessageItem>().map((item) => item.text), <String>[
      'one',
      'two',
    ]);
    expect(view().status, SessionStatus.running);
    expect(view().canForceStop, isTrue);
  });

  test('a chat that cannot be opened shows the error', () async {
    repository.openError = StateError('no such chat');
    await open();

    expect(controller.state, isA<Chat$ErrorState>());
    expect((controller.state as Chat$ErrorState).error, isA<StateError>());
  });

  test('a first runtime that cannot be folded shows the error', () async {
    await open();
    repository.runtimes.add(_runtime(events: _Throwing(<SessionEvent>[_prompt(1, 'x')])));
    await pumpEventQueue();

    expect(controller.state, isA<Chat$ErrorState>());
  });

  test('opening again with keepView keeps the view until the new runtime arrives', () async {
    await open();
    repository.runtimes.add(_runtime(events: <SessionEvent>[_prompt(1, 'kept')]));
    await pumpEventQueue();

    controller.open(1, keepView: true);
    await pumpEventQueue();
    expect(repository.watched, 2);
    expect(view().items.whereType<UserMessageItem>().single.text, 'kept');

    repository.runtimes.add(_runtime(status: SessionStatus.cold));
    await pumpEventQueue();
    // The first runtime of the new watch shows at once.
    expect(view().status, SessionStatus.cold);
    expect(view().items, isEmpty);
  });
}

/// A journal whose reading throws, as a corrupt one could in the fold.
final class _Throwing extends ListBase<SessionEvent> {
  _Throwing(this._events);

  final List<SessionEvent> _events;

  @override
  int get length => _events.length;

  @override
  set length(int value) => throw UnsupportedError('read-only');

  @override
  SessionEvent operator [](int index) => throw StateError('corrupt journal');

  @override
  void operator []=(int index, SessionEvent value) => throw UnsupportedError('read-only');
}
