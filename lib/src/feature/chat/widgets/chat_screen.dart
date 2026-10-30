import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_recovery_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_feed.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_problem_banner.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_status_line.dart';
import 'package:flutter_code_agent/src/feature/file_mention/controller/file_mention_controller.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/prompt_composer.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_code_agent/src/feature/session_config/widgets/bypass_gate_banner.dart';
import 'package:flutter_code_agent/src/feature/session_config/widgets/composer_toolbar.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_sidebar_footer.dart';

/// {@template chat_screen}
/// Feed, problem banner, status line and composer of one chat.
/// {@endtemplate}
class ChatScreen extends StatefulWidget {
  /// {@macro chat_screen}
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final _scope = ChatConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) => StateConsumer<ChatController, ChatState>(
    controller: _scope.chatController,
    builder: (context, state, _) => switch (state) {
      Chat$CompletedState(:final view) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ChatFeed(items: view.items, onAnswerPermission: _scope.answerPermission),
          ),
          StateConsumer<ChatRecoveryController, ChatRecoveryState>(
            controller: _scope.recoveryController,
            builder: (context, recovery, _) => ChatProblemBanner(
              view: view,
              busy: recovery is ChatRecovery$InProgressState,
              loginFailed: recovery is ChatRecovery$ErrorState,
              loginOutput: switch (recovery) {
                ChatRecovery$InProgressState(:final output) => output,
                ChatRecovery$ErrorState(:final output) => output,
                _ => const <String>[],
              },
              loginMethods: _scope.loginMethods(view.agentId),
              onRetry: _scope.retry,
              onStartNewAgentSession: _scope.startNewAgentSession,
              onForceStop: () => _scope.forceStop(view.agentId),
              onLogin: (method) => _scope.login(view.agentId, method),
              onRepeatPrompt: _scope.repeatPrompt,
            ),
          ),
          ChatStatusLine(status: view.status, preparing: view.preparingTurn),
          if (view.bypassBlocked) BypassGateBanner(onAllow: _scope.allowBypass),
          StateConsumer<FileMentionController, FileMentionState>(
            controller: _scope.fileMentionController,
            builder: (context, _, _) => PromptComposer(
              controller: _scope.textController,
              focusNode: _scope.composerFocus,
              canSend:
                  !view.bypassBlocked &&
                  switch (view.status) {
                    SessionStatus.cold || SessionStatus.idle || SessionStatus.error => true,
                    _ => false,
                  },
              canStop:
                  view.status == SessionStatus.running ||
                  view.status == SessionStatus.awaitingPermission,
              onSend: _scope.send,
              onStop: _scope.stop,
              mentionFiles: _scope.fileMentionController.files,
              onMentionStart: _scope.refreshFiles,
              onCycleMode: view.canChangeConfig && permissionModeOf(view.configOptions) != null
                  ? _scope.cycleMode
                  : null,
              toolbar: <Widget>[
                ComposerToolbar(
                  agentName: agentDisplayName(view.agentId),
                  agentLocked: view.agentLocked,
                  options: view.configOptions,
                  enabled: view.canChangeConfig,
                  onChanged: _scope.setConfig,
                  onAttach: _scope.attachFile,
                  onMakeDefault: _scope.makeDefault,
                ),
              ],
            ),
          ),
        ],
      ),
      Chat$ErrorState(:final error) => Center(
        child: Text(error?.toString() ?? Localization.of(context).somethingWentWrong),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    },
  );
}
