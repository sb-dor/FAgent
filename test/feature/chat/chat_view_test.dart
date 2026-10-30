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
}
