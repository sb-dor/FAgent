import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_problem_banner.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_status_line.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

ChatView _view(SessionStatus status, {bool canRetryPrompt = false, bool bypassBlocked = false}) =>
    ChatView(
      sessionId: 1,
      agentId: 'claude',
      items: const <ChatItem>[],
      status: status,
      problem: status == SessionStatus.needsAuth
          ? const SessionProblem(SessionProblemKind.auth, 'Authentication required')
          : null,
      canRetryPrompt: canRetryPrompt,
      bypassBlocked: bypassBlocked,
    );

Widget _banner(
  ChatView view, {
  List<String> loginOutput = const <String>[],
  ValueChanged<String>? onLogin,
  bool busy = false,
}) => ChatProblemBanner(
  view: view,
  busy: busy,
  loginFailed: false,
  loginMethods: const <String>['claude-ai-login', 'console-login'],
  loginOutput: loginOutput,
  onRetry: () {},
  onStartNewAgentSession: () {},
  onForceStop: () {},
  onLogin: onLogin ?? (_) {},
  onRepeatPrompt: () {},
);

void main() {
  testWidgets('a chat that needs a login offers both methods', (tester) async {
    final methods = <String>[];
    await tester.pumpWidget(testApp(_banner(_view(SessionStatus.needsAuth), onLogin: methods.add)));

    await tester.tap(find.text('Log in with Claude.ai'));
    await tester.tap(find.text('Log in with Anthropic Console'));

    expect(methods, <String>['claude-ai-login', 'console-login']);
  });

  testWidgets('the login output is shown while it runs', (tester) async {
    await tester.pumpWidget(
      testApp(
        _banner(
          _view(SessionStatus.needsAuth),
          busy: true,
          loginOutput: const <String>['Opening https://claude.ai/oauth …', 'Waiting'],
        ),
      ),
    );

    expect(find.text('Opening https://claude.ai/oauth …\nWaiting'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Log in with Claude.ai'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a prompt held by the bypass gate is not offered for repeating', (tester) async {
    await tester.pumpWidget(
      testApp(_banner(_view(SessionStatus.idle, canRetryPrompt: true, bypassBlocked: true))),
    );

    expect(find.text('Repeat the last prompt'), findsNothing);

    await tester.pumpWidget(testApp(_banner(_view(SessionStatus.idle, canRetryPrompt: true))));
    expect(find.text('Repeat the last prompt'), findsOneWidget);
  });

  testWidgets('a turn that is being prepared says so, in Russian too', (tester) async {
    await tester.pumpWidget(
      testApp(
        const ChatStatusLine(status: SessionStatus.running, preparing: true),
        locale: const Locale('ru'),
      ),
    );

    expect(find.text('Готовлю ход…'), findsOneWidget);
  });
}
