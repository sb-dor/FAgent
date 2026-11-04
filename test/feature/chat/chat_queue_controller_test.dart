import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_queue_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/models/queued_prompt.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/data/prompt_sending_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// One prompt the queue handed to the agent.
typedef _Sent = ({int sessionId, String text, List<Map<String, Object?>> resources});

/// Records the prompts; each send completes when the test says (the turn ends), or throws
/// [failWith] once.
final class _RecordingSending implements IPromptSendingRepository {
  final List<_Sent> sent = <_Sent>[];
  Error? failWith;

  @override
  Future<void> send(
    int sessionId,
    String text, {
    List<Map<String, Object?>> resources = const <Map<String, Object?>>[],
  }) async {
    sent.add((sessionId: sessionId, text: text, resources: resources));
    if (failWith case final error?) {
      failWith = null;
      throw error;
    }
  }

  @override
  Future<void> repeat(int sessionId) async {}

  @override
  Future<void> stop(int sessionId) async {}

  @override
  Future<void> forceStop(String agentId) async {}
}

const _link = <String, Object?>{
  'type': 'resource_link',
  'uri': 'file:///p/lib/main.dart',
  'name': 'main.dart',
};

QueuedPrompt _prompt(String text, {List<Map<String, Object?>> resources = const []}) =>
    QueuedPrompt(text: text, resources: resources);

void main() {
  late _RecordingSending sending;
  late ValueNotifier<SessionStatus> status;
  late ChatQueueController queue;

  setUp(() {
    sending = _RecordingSending();
    status = ValueNotifier<SessionStatus>(SessionStatus.running);
    queue = ChatQueueController(sessionId: 1, repository: sending)..follow(status);
  });

  tearDown(() {
    queue.dispose();
    status.dispose();
  });

  /// Lets the queue's sends run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// One turn of the agent: it starts (the queue's prompt is taken) and ends with [end].
  Future<void> turn({SessionStatus end = SessionStatus.idle}) async {
    status
      ..value = SessionStatus.running
      ..value = end;
    await settle();
  }

  test('a turn ending idle sends the first queued, then the next after its turn', () async {
    queue
      ..add(_prompt('first', resources: const <Map<String, Object?>>[_link]))
      ..add(_prompt('second'));

    status.value = SessionStatus.idle;
    await settle();

    expect(sending.sent.map((s) => s.text), <String>['first']);
    expect(sending.sent.single.resources, const <Map<String, Object?>>[_link]);
    expect(queue.state.items.map((p) => p.text), <String>['second']);

    await turn();

    expect(sending.sent.map((s) => s.text), <String>['first', 'second']);
    expect(queue.state.items, isEmpty);
    expect(queue.state.paused, isFalse);
  });

  test('an awaited permission is part of the turn: its end sends the next', () async {
    queue.add(_prompt('next'));

    status.value = SessionStatus.awaitingPermission;
    await settle();
    expect(sending.sent, isEmpty);

    status.value = SessionStatus.idle;
    await settle();
    expect(sending.sent.map((s) => s.text), <String>['next']);
  });

  test('the setup of a turn reaching idle is not the end of the turn', () async {
    status.value = SessionStatus.starting;
    queue.add(_prompt('later'));

    status
      ..value = SessionStatus.creating
      ..value = SessionStatus.idle;
    await settle();

    expect(sending.sent, isEmpty);
    expect(queue.state.items, hasLength(1));

    await turn();
    expect(sending.sent.map((s) => s.text), <String>['later']);
  });

  group('error and needsAuth pause', () {
    for (final failure in <SessionStatus>[SessionStatus.error, SessionStatus.needsAuth]) {
      test(failure.name, () async {
        queue.add(_prompt('next'));

        status.value = failure;
        await settle();

        expect(sending.sent, isEmpty);
        expect(queue.state.paused, isTrue);
        expect(queue.state.items, hasLength(1));

        // It does not continue by itself after the failure, not even after a good turn.
        await turn();
        expect(sending.sent, isEmpty);
        expect(queue.state.paused, isTrue);
      });
    }

    test('a failed setup of the turn pauses too', () async {
      status.value = SessionStatus.starting;
      queue.add(_prompt('next'));

      status.value = SessionStatus.needsAuth;
      await settle();

      expect(queue.state.paused, isTrue);
    });
  });

  test('a user stop pauses', () async {
    queue
      ..add(_prompt('next'))
      ..pauseAfterStop();

    status
      ..value = SessionStatus.cancelling
      ..value = SessionStatus.idle;
    await settle();

    expect(sending.sent, isEmpty);
    expect(queue.state.paused, isTrue);
  });

  test('a stop that ends the turn before it is cancelling still pauses', () async {
    queue
      ..add(_prompt('next'))
      ..pauseAfterStop();

    status.value = SessionStatus.idle;
    await settle();

    expect(sending.sent, isEmpty);
    expect(queue.state.paused, isTrue);
  });

  test('a stop pressed in an earlier turn does not pause the next one', () async {
    queue.pauseAfterStop();
    status
      ..value = SessionStatus.cancelling
      ..value = SessionStatus.idle;
    await settle();

    status.value = SessionStatus.running;
    queue.add(_prompt('next'));
    status.value = SessionStatus.idle;
    await settle();

    expect(sending.sent.map((s) => s.text), <String>['next']);
    expect(queue.state.paused, isFalse);
  });

  test('send next resumes', () async {
    queue
      ..add(_prompt('first'))
      ..add(_prompt('second'));
    status.value = SessionStatus.error;
    await settle();
    expect(queue.state.paused, isTrue);

    queue.sendNext();
    await settle();

    expect(sending.sent.map((s) => s.text), <String>['first']);
    expect(queue.state.paused, isFalse);
    expect(queue.state.items.map((p) => p.text), <String>['second']);

    // Resumed: the next good turn end sends the rest.
    status.value = SessionStatus.starting;
    await turn();
    expect(sending.sent.map((s) => s.text), <String>['first', 'second']);
  });

  test('send next while the agent works only resumes', () async {
    queue
      ..add(_prompt('first'))
      ..pauseAfterStop();
    status
      ..value = SessionStatus.cancelling
      ..value = SessionStatus.idle;
    await settle();
    status.value = SessionStatus.running;

    queue.sendNext();
    await settle();

    expect(sending.sent, isEmpty);
    expect(queue.state.paused, isFalse);

    status.value = SessionStatus.idle;
    await settle();
    expect(sending.sent.map((s) => s.text), <String>['first']);
  });

  test('edit returns the item and removes it', () async {
    queue
      ..add(_prompt('first'))
      ..add(_prompt('second', resources: const <Map<String, Object?>>[_link]));

    final edited = queue.edit(1);

    expect(edited, _prompt('second', resources: const <Map<String, Object?>>[_link]));
    expect(queue.state.items.map((p) => p.text), <String>['first']);
    expect(queue.edit(5), isNull);
  });

  test('remove', () async {
    queue
      ..add(_prompt('first'))
      ..add(_prompt('second'))
      ..remove(0);

    expect(queue.state.items.map((p) => p.text), <String>['second']);

    status.value = SessionStatus.idle;
    await settle();
    expect(sending.sent.map((s) => s.text), <String>['second']);
  });

  test('an emptied queue is no longer paused', () async {
    queue.add(_prompt('first'));
    status.value = SessionStatus.error;
    await settle();

    queue.remove(0);

    expect(queue.state.paused, isFalse);
  });

  test('a message queued after the turn already ended is sent at once', () async {
    status.value = SessionStatus.idle;
    await settle();

    queue.add(_prompt('late'));
    await settle();

    expect(sending.sent.map((s) => s.text), <String>['late']);
  });

  test('a message queued after the turn failed waits paused', () async {
    status.value = SessionStatus.error;
    await settle();

    queue.add(_prompt('late'));
    await settle();

    expect(sending.sent, isEmpty);
    expect(queue.state.paused, isTrue);
  });

  test('a prompt the agent refused to take goes back to the front, paused', () async {
    queue
      ..add(_prompt('first'))
      ..add(_prompt('second'));
    sending.failWith = StateError('Cannot send a prompt while the session is running');

    status.value = SessionStatus.idle;
    await settle();

    expect(queue.state.items.map((p) => p.text), <String>['first', 'second']);
    expect(queue.state.paused, isTrue);
  });

  test('a queue of chat A is never sent into chat B', () async {
    final statusB = ValueNotifier<SessionStatus>(SessionStatus.idle);
    final queueB = ChatQueueController(sessionId: 2, repository: sending)..follow(statusB);
    addTearDown(() {
      queueB.dispose();
      statusB.dispose();
    });
    queue.add(_prompt('for A'));

    // The user works in chat B meanwhile.
    statusB
      ..value = SessionStatus.running
      ..value = SessionStatus.idle;
    await settle();
    expect(sending.sent, isEmpty);

    status.value = SessionStatus.idle;
    await settle();

    expect(sending.sent, hasLength(1));
    expect(sending.sent.single.sessionId, 1);
    expect(sending.sent.single.text, 'for A');
  });

  group('ChatQueueRegistry', () {
    late ChatQueueRegistry registry;
    late Map<int, ValueNotifier<SessionStatus>> statuses;

    setUp(() {
      statuses = <int, ValueNotifier<SessionStatus>>{};
      registry = ChatQueueRegistry(
        create: (sessionId) => ChatQueueController(sessionId: sessionId, repository: sending),
      );
    });

    tearDown(() {
      registry.dispose();
      for (final notifier in statuses.values) {
        notifier.dispose();
      }
    });

    ChatQueueController open(int sessionId) {
      final notifier = statuses[sessionId] ??= ValueNotifier<SessionStatus>(SessionStatus.running);
      return registry.acquire(sessionId)..follow(notifier);
    }

    test('the same chat gets the same queue', () {
      final first = open(1);
      expect(open(1), same(first));
    });

    test('sessionIds lists the chats with queued messages', () {
      open(1).add(_prompt('a'));
      open(2);

      expect(registry.sessionIds, <int>{1});
    });

    test('a queue of chat A is sent into A after the user switched to chat B', () async {
      open(1).add(_prompt('for A'));
      // The user switches: chat A's widget is gone, chat B's is shown.
      registry.release(1);
      open(2);
      await settle();
      expect(registry.sessionIds, <int>{1});

      statuses[2]!.value = SessionStatus.idle;
      statuses[1]!.value = SessionStatus.idle;
      await settle();

      expect(sending.sent.map((s) => (s.sessionId, s.text)), <(int, String)>[(1, 'for A')]);
      expect(registry.sessionIds, isEmpty);
    });

    test('an empty queue nobody shows is disposed; a held one is kept', () async {
      final shown = open(1);
      registry.release(1);
      await settle();
      expect(shown.isDisposed, isTrue);

      final held = open(2)..add(_prompt('a'));
      registry.release(2);
      await settle();
      expect(held.isDisposed, isFalse);
      expect(open(2), same(held));
    });

    test('a queue nobody shows is disposed once it has sent everything', () async {
      final queue = open(1)..add(_prompt('a'));
      registry.release(1);

      statuses[1]!.value = SessionStatus.idle;
      await settle();

      expect(queue.isDisposed, isTrue);
      expect(registry.sessionIds, isEmpty);
    });
  });
}
