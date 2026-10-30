import 'dart:convert';
import 'dart:io';

import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

/// Turns a recorded fixture into journal events the way AgentHub writes them.
List<SessionEvent> _fixture(String name) {
  final events = <SessionEvent>[];
  for (final line in File('test/fixtures/acp/$name.ndjson').readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final entry = jsonDecode(line) as Map<String, Object?>;
    final payload = (entry['payload']! as Map).cast<String, Object?>();
    final params = (payload['params'] as Map?)?.cast<String, Object?>();
    final (origin, kind, body) = switch (payload['method']) {
      'session/prompt' => (SessionEventOrigin.user, SessionEventKind.prompt, params!),
      'session/request_permission' => (
        SessionEventOrigin.agent,
        SessionEventKind.permissionRequest,
        <String, Object?>{'requestId': 'fixture#1#${payload['id']}', 'params': params},
      ),
      _ => (SessionEventOrigin.agent, '${(params?['update'] as Map?)?['sessionUpdate']}', payload),
    };
    events.add(
      SessionEvent(
        seq: events.length,
        origin: origin,
        kind: kind,
        payload: body,
        createdAt: DateTime(2026),
      ),
    );
  }
  return events;
}

SessionEvent _update(int seq, Map<String, Object?> update) => SessionEvent(
  seq: seq,
  origin: SessionEventOrigin.agent,
  kind: '${update['sessionUpdate']}',
  payload: <String, Object?>{
    'method': 'session/update',
    'params': <String, Object?>{'sessionId': 's', 'update': update},
  },
  createdAt: DateTime(2026),
);

SessionEvent _app(int seq, String kind, Map<String, Object?> payload) => SessionEvent(
  seq: seq,
  origin: SessionEventOrigin.app,
  kind: kind,
  payload: payload,
  createdAt: DateTime(2026),
);

Map<String, Object?> _chunk(String text, {String? id, bool thought = false}) => <String, Object?>{
  'sessionUpdate': thought ? 'agent_thought_chunk' : 'agent_message_chunk',
  'content': <String, Object?>{'type': 'text', 'text': text},
  'messageId': ?id,
};

void main() {
  group('recorded Claude sessions', () {
    test('a simple turn is a user message and one agent message', () {
      final items = ChatTranscript.fold(_fixture('simple_turn'));

      expect(items.map((i) => i.runtimeType), <Type>[UserMessageItem, AgentMessageItem]);
      expect((items.last as AgentMessageItem).text.toLowerCase(), contains('pong'));
    });

    test('an edit is one tool call with its diff, a permission card and the reply', () {
      final events = _fixture('edit_file');
      final requestId = events
          .firstWhere((e) => e.kind == SessionEventKind.permissionRequest)
          .payload['requestId']!;
      events.add(
        _app(events.length, SessionEventKind.permissionResolution, <String, Object?>{
          'requestId': requestId,
          'outcome': 'selected',
          'optionId': 'allow-once',
        }),
      );

      final items = ChatTranscript.fold(events);

      expect(items.map((i) => i.runtimeType), <Type>[
        UserMessageItem,
        ToolCallItem,
        PermissionItem,
        AgentMessageItem,
      ]);
      final tool = items[1] as ToolCallItem;
      expect(tool.status, 'completed');
      expect(tool.title, startsWith('Write '));
      expect(tool.diffs.single.oldText, isNull);
      expect(tool.diffs.single.newText, 'hi');
      expect(tool.rawOutput, contains('File created successfully'));
      final permission = items[2] as PermissionItem;
      expect(permission.state, PermissionState.selected);
      expect(permission.selectedOptionId, 'allow-once');
      expect(permission.diffs.single.path, endsWith('hello.txt'));
      expect(permission.options.first.allows, isTrue);
      expect(
        (items.last as AgentMessageItem).text,
        startsWith('I created `hello.txt` in the current directory'),
      );
    });
  });

  test('chunks merge per messageId and a new id starts a new message', () {
    final items = ChatTranscript.fold(<SessionEvent>[
      _update(0, _chunk('Hel', id: 'a')),
      _update(1, _chunk('lo', id: 'a')),
      _update(2, _chunk('thinking', id: 'a', thought: true)),
      _update(3, _chunk('Second', id: 'b')),
      _update(4, _chunk(' part', id: 'b')),
    ]);

    expect(items, hasLength(3));
    expect((items[0] as AgentMessageItem).text, 'Hello');
    expect((items[1] as AgentThoughtItem).text, 'thinking');
    expect((items[2] as AgentMessageItem).text, 'Second part');
  });

  test('thought duration comes from the chunk times', () {
    final start = DateTime(2026);
    SessionEvent at(int seq, int seconds, Map<String, Object?> update) => SessionEvent(
      seq: seq,
      origin: SessionEventOrigin.agent,
      kind: '${update['sessionUpdate']}',
      payload: <String, Object?>{
        'method': 'session/update',
        'params': <String, Object?>{'sessionId': 's', 'update': update},
      },
      createdAt: start.add(Duration(seconds: seconds)),
    );

    final items = ChatTranscript.fold(<SessionEvent>[
      at(0, 0, _chunk('a', id: 't1', thought: true)),
      at(1, 5, _chunk('b', id: 't1', thought: true)),
      at(2, 12, _chunk('c', id: 't1', thought: true)),
      at(3, 13, _chunk('single', id: 't2', thought: true)),
    ]);

    expect((items[0] as AgentThoughtItem).duration, const Duration(seconds: 12));
    expect((items[1] as AgentThoughtItem).duration, isNull);
  });

  test('a plan is updated in place within a turn', () {
    Map<String, Object?> plan(String status) => <String, Object?>{
      'sessionUpdate': 'plan',
      'entries': <Object?>[
        <String, Object?>{'content': 'Write tests', 'status': status, 'priority': 'high'},
      ],
    };
    final items = ChatTranscript.fold(<SessionEvent>[
      _update(0, plan('pending')),
      _update(1, _chunk('working')),
      _update(2, plan('completed')),
    ]);

    expect(items.map((i) => i.runtimeType), <Type>[PlanItem, AgentMessageItem]);
    expect((items.first as PlanItem).entries.single.status, 'completed');
  });

  test('unanswered permission requests from an earlier run are stale', () {
    final request = SessionEvent(
      seq: 0,
      origin: SessionEventOrigin.agent,
      kind: SessionEventKind.permissionRequest,
      payload: const <String, Object?>{
        'requestId': 'claude#1#7',
        'params': <String, Object?>{
          'toolCall': <String, Object?>{
            'toolCallId': 't',
            'title': 'Run tests',
            'rawInput': <String, Object?>{'command': 'flutter test'},
          },
          'options': <Object?>[
            <String, Object?>{'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
          ],
        },
      },
      createdAt: DateTime(2026),
    );

    final stale = ChatTranscript.fold(<SessionEvent>[request]).single as PermissionItem;
    final open =
        ChatTranscript.fold(
              <SessionEvent>[request],
              openPermissionIds: <String>{'claude#1#7'},
            ).single
            as PermissionItem;

    expect(stale.state, PermissionState.stale);
    expect(open.state, PermissionState.pending);
    expect(open.command, 'flutter test');
  });

  test('turn ends, system notes and unknown events', () {
    final items = ChatTranscript.fold(<SessionEvent>[
      _app(0, SessionEventKind.system, <String, Object?>{
        'type': 'turn_end',
        'stopReason': 'end_turn',
      }),
      _app(1, SessionEventKind.system, <String, Object?>{
        'type': 'turn_end',
        'stopReason': 'cancelled',
      }),
      _app(2, SessionEventKind.system, <String, Object?>{
        'type': 'error',
        'message': 'Agent stopped',
      }),
      _update(3, <String, Object?>{'sessionUpdate': 'usage_update', 'used': 1}),
      _update(4, <String, Object?>{'sessionUpdate': 'brand_new_update'}),
    ]);

    expect(items.map((i) => i.runtimeType), <Type>[TurnEndItem, SystemItem, UnknownItem]);
    expect((items[0] as TurnEndItem).stopReason, 'cancelled');
    expect((items[1] as SystemItem).message, 'Agent stopped');
    expect((items[2] as UnknownItem).kind, 'brand_new_update');
  });

  test('a prompt keeps its text and attached files', () {
    final item =
        ChatTranscript.fold(<SessionEvent>[
              SessionEvent(
                seq: 0,
                origin: SessionEventOrigin.user,
                kind: SessionEventKind.prompt,
                payload: const <String, Object?>{
                  'sessionId': 's',
                  'prompt': <Object?>[
                    <String, Object?>{'type': 'text', 'text': 'Fix the bug in '},
                    <String, Object?>{
                      'type': 'resource_link',
                      'uri': 'file:///p/lib/main.dart',
                      'name': 'main.dart',
                    },
                  ],
                },
                createdAt: DateTime(2026),
              ),
            ]).single
            as UserMessageItem;

    expect(item.text, 'Fix the bug in ');
    expect(item.resources, <String>['file:///p/lib/main.dart']);
  });

  test('changed files of a turn become one item', () {
    final items = ChatTranscript.fold(<SessionEvent>[
      _app(0, SessionEventKind.turnFiles, <String, Object?>{
        'files': <Object?>[
          <String, Object?>{'path': 'lib/main.dart', 'status': ' M'},
          <String, Object?>{'path': 'README.md', 'status': '??'},
        ],
      }),
    ]);

    final files = (items.single as TurnFilesItem).files;
    expect(files.map((f) => f.path), <String>['lib/main.dart', 'README.md']);
  });

  test('the git root of a turn is kept; old journals have none', () {
    final items = ChatTranscript.fold(<SessionEvent>[
      _app(0, SessionEventKind.turnFiles, <String, Object?>{
        'root': '/repo',
        'files': <Object?>[
          <String, Object?>{'path': 'a.dart', 'status': ' M'},
        ],
      }),
      _app(1, SessionEventKind.turnFiles, <String, Object?>{
        'files': <Object?>[
          <String, Object?>{'path': 'b.dart', 'status': ' M'},
        ],
      }),
    ]);

    expect((items[0] as TurnFilesItem).root, '/repo');
    expect((items[1] as TurnFilesItem).root, isNull);
  });
}
