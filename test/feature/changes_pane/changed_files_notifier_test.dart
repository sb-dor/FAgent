import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/controller/changed_files_notifier.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatHandle handle(List<ChatItem> items) => ChatHandle(
    sessionId: 1,
    view: ChatView(sessionId: 1, agentId: 'claude', items: items, status: SessionStatus.idle),
    insertDraft: (_) {},
  );

  test('files are recomputed when the project root arrives late', () {
    final chat = ValueNotifier<ChatHandle?>(
      handle(const <ChatItem>[
        TurnFilesItem(
          1,
          files: <TurnFile>[TurnFile(path: 'lib/a.dart', status: ' M')],
        ),
      ]),
    );
    final root = ValueNotifier<String>('');
    final notifier = ChangedFilesNotifier(
      handle: chat,
      projectRoot: () => root.value,
      rootChanges: root,
    );
    addTearDown(() {
      notifier.dispose();
      chat.dispose();
      root.dispose();
    });
    expect(notifier.value, isEmpty);

    root.value = '/p';

    expect(notifier.value.map((f) => f.path), <String>['/p/lib/a.dart']);
  });

  test('an unchanged feed and root do not notify', () {
    final chat = ValueNotifier<ChatHandle?>(handle(const <ChatItem>[]));
    final root = ValueNotifier<String>('/p');
    final notifier = ChangedFilesNotifier(
      handle: chat,
      projectRoot: () => root.value,
      rootChanges: root,
    );
    addTearDown(() {
      notifier.dispose();
      chat.dispose();
      root.dispose();
    });
    var notified = 0;
    notifier.addListener(() => notified++);

    root.notifyListeners();
    chat.notifyListeners();

    expect(notified, 0);
  });
}
