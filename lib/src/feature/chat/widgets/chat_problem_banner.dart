import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';

/// {@template chat_problem_banner}
/// Why the chat cannot continue and what can be done about it: retry, a new
/// agent session after a failed load, login, force-stop, repeating a prompt.
/// {@endtemplate}
class ChatProblemBanner extends StatelessWidget {
  /// {@macro chat_problem_banner}
  const ChatProblemBanner({
    required this.view,
    required this.busy,
    required this.loginFailed,
    required this.onRetry,
    required this.onStartNewAgentSession,
    required this.onForceStop,
    required this.onLogin,
    required this.onRepeatPrompt,
    this.loginMethods = const <String>[],
    this.loginOutput = const <String>[],
    super.key,
  });

  /// The chat.
  final ChatView view;

  /// A recovery action is running.
  final bool busy;

  /// The last login attempt failed.
  final bool loginFailed;

  final VoidCallback onRetry;
  final VoidCallback onStartNewAgentSession;
  final VoidCallback onForceStop;

  /// Logs in with a method id.
  final ValueChanged<String> onLogin;

  /// Login methods offered when the agent needs a login.
  final List<String> loginMethods;

  /// Output of the running or failed login (it may show a link or a code).
  final List<String> loginOutput;
  final VoidCallback onRepeatPrompt;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final problem = view.problem;
    final status = view.status;
    final actions = <Widget>[
      if (status == SessionStatus.setupFailed || status == SessionStatus.error)
        FilledButton.tonal(onPressed: busy ? null : onRetry, child: Text(localization.retry)),
      if (status == SessionStatus.setupFailed && problem?.kind == SessionProblemKind.notFound)
        OutlinedButton(
          onPressed: busy ? null : onStartNewAgentSession,
          child: Text(localization.startNewAgentSession),
        ),
      if (status == SessionStatus.needsAuth)
        for (final method in loginMethods)
          FilledButton.tonal(
            onPressed: busy ? null : () => onLogin(method),
            child: Text(switch (method) {
              'claude-ai-login' => localization.loginWithClaudeAi,
              'console-login' => localization.loginWithConsole,
              _ => method,
            }),
          ),
      if (view.canForceStop)
        OutlinedButton(onPressed: onForceStop, child: Text(localization.forceStop)),
      // A prompt held back by the bypass gate is sent by its banner.
      if (view.canRetryPrompt && !view.bypassBlocked)
        FilledButton.tonal(onPressed: onRepeatPrompt, child: Text(localization.repeatPrompt)),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final message = switch (status) {
      SessionStatus.needsAuth when busy => localization.loggingIn,
      SessionStatus.needsAuth when loginFailed => localization.loginFailed,
      SessionStatus.needsAuth => localization.problemNeedsAuth,
      _ when problem?.kind == SessionProblemKind.notFound => localization.problemNotFound,
      _ => problem?.message ?? localization.problemTitle,
    };
    final details = <String>[?problem?.hint, ...?problem?.details];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: context.colors.dangerSoft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(message),
                  if (details.isNotEmpty)
                    Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        dense: true,
                        tilePadding: EdgeInsets.zero,
                        title: Text(localization.details, style: theme.textTheme.labelMedium),
                        children: <Widget>[
                          SelectableText(
                            details.join('\n'),
                            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo'),
                          ),
                        ],
                      ),
                    ),
                  if (status == SessionStatus.needsAuth && loginOutput.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: SelectableText(
                          loginOutput.join('\n'),
                          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo'),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
