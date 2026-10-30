import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_test/flutter_test.dart';

ChatView _view(SessionStatus status, [List<ChatItem> items = const <ChatItem>[]]) =>
    ChatView(sessionId: 1, agentId: 'claude', items: items, status: status);

void main() {
  test('the agent is locked once the user has written', () {
    expect(_view(SessionStatus.cold).agentLocked, isFalse);
    expect(
      _view(SessionStatus.idle, const <ChatItem>[AgentMessageItem(1, text: 'hi')]).agentLocked,
      isFalse,
    );
    expect(
      _view(SessionStatus.idle, const <ChatItem>[UserMessageItem(1, text: 'hi')]).agentLocked,
      isTrue,
    );
  });

  test('settings change while the agent session is up', () {
    for (final status in SessionStatus.values) {
      final expected =
          status == SessionStatus.idle ||
          status == SessionStatus.running ||
          status == SessionStatus.awaitingPermission;
      expect(_view(status).canChangeConfig, expected, reason: '$status');
    }
  });

  group('pendingPermission', () {
    PermissionItem permission(int seq, PermissionState state) => PermissionItem(
      seq,
      requestId: 'r$seq',
      title: 't',
      options: const <PermissionOptionView>[],
      state: state,
    );

    test('is the latest request that still waits', () {
      final view = _view(SessionStatus.awaitingPermission, <ChatItem>[
        permission(1, PermissionState.pending),
        permission(2, PermissionState.pending),
        permission(3, PermissionState.selected),
      ]);
      expect(view.pendingPermission?.requestId, 'r2');
    });

    test('is null when nothing waits', () {
      expect(_view(SessionStatus.idle).pendingPermission, isNull);
      expect(
        _view(SessionStatus.idle, <ChatItem>[
          permission(1, PermissionState.stale),
        ]).pendingPermission,
        isNull,
      );
    });
  });

  group('PermissionItem keys', () {
    PermissionItem withKinds(List<String> kinds) => PermissionItem(
      1,
      requestId: 'r',
      title: 't',
      options: <PermissionOptionView>[
        for (final (i, kind) in kinds.indexed)
          PermissionOptionView(optionId: '$i', name: kind, kind: kind),
      ],
    );

    test('Enter takes the first allow_once, Esc the first reject_once', () {
      final item = withKinds(<String>[
        'allow_always',
        'reject_always',
        'allow_once',
        'reject_once',
      ]);
      expect(item.acceptOption?.optionId, '2');
      expect(item.rejectOption?.optionId, '3');
    });

    test('without allow_once the first allowing option is taken', () {
      final item = withKinds(<String>['reject_always', 'allow_always']);
      expect(item.acceptOption?.optionId, '1');
      expect(item.rejectOption?.optionId, '0');
    });

    test('without a rejecting option Esc has nothing to take', () {
      expect(withKinds(<String>['allow_once']).rejectOption, isNull);
      expect(withKinds(<String>['reject_once']).acceptOption, isNull);
    });
  });
}
