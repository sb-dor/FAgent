import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/acp/live_session.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/agents/controller/agents_controller.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_login_methods_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_queue_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_recovery_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_feed.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_problem_banner.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_queue_view.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_status_line.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_unsaved_files_bar.dart';
import 'package:flutter_code_agent/src/feature/file_mention/controller/file_mention_controller.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_image.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/run_mentions.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/prompt_composer.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_code_agent/src/feature/session_config/widgets/bypass_gate_banner.dart';
import 'package:flutter_code_agent/src/feature/session_config/widgets/composer_toolbar.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/chat_skills_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
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

  /// Answers the latest waiting request with its Enter (`allow_once`) or Esc (`reject_once`)
  /// option; `null` when there is nothing to answer.
  VoidCallback? _answerPending(PermissionItem? pending, {required bool accept}) {
    final option = accept ? pending?.acceptOption : pending?.rejectOption;
    return pending == null || option == null
        ? null
        : () => _scope.answerPermission(pending.requestId, option.optionId);
  }

  /// Whether the chat takes a prompt now.
  static bool _canSend(ChatView view) =>
      !view.bypassBlocked &&
      // A removed agent cannot take a message: it would be lost.
      view.problem?.kind != SessionProblemKind.removed &&
      switch (view.status) {
        SessionStatus.cold || SessionStatus.idle || SessionStatus.error => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) => StateConsumer<ChatController, ChatState>(
    controller: _scope.chatController,
    builder: (context, state, _) => switch (state) {
      Chat$CompletedState(:final view) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ValueListenableBuilder<ChatSkills>(
              valueListenable: _scope.chatSkills,
              builder: (context, chatSkills, _) => ChatFeed(
                items: view.items,
                onAnswerPermission: _scope.answerPermission,
                onRejectAndSay: _scope.rejectAndSay,
                projectRoot: _scope.projectRoot,
                onOpenChange: _scope.onOpenChange,
                skills: chatSkills,
                onOpenSkill: _scope.canOpenSkills ? (id) => _scope.openSkills(itemId: id) : null,
                keyboardRequestId: view.pendingPermission?.requestId,
              ),
            ),
          ),
          // Rebuilt when the agent's check finds its sign-in methods.
          StateConsumer<ChatLoginMethodsController, Map<String, List<AgentLoginMethod>>>(
            controller: _scope.loginMethodsController,
            builder: (context, methods, _) =>
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
                    loginMethods: methods[view.agentId] ?? const <AgentLoginMethod>[],
                    onRetry: _scope.retry,
                    onStartNewAgentSession: _scope.startNewAgentSession,
                    onForceStop: () => _scope.forceStop(view.agentId),
                    onLogin: (method) => _scope.login(view.agentId, method),
                    onCancelLogin: recovery is ChatRecovery$InProgressState && recovery.cancellable
                        ? () => _scope.cancelLogin(view.agentId)
                        : null,
                    onRepeatPrompt: _scope.repeatPrompt,
                  ),
                ),
          ),
          ChatStatusLine(status: view.status, preparing: view.preparingTurn),
          if (view.bypassBlocked) BypassGateBanner(onAllow: _scope.allowBypass),
          StateConsumer<ChatQueueController, ChatQueueState>(
            controller: _scope.queueController,
            builder: (context, queue, _) => ChatQueueView(
              items: queue.items,
              paused: queue.paused,
              onEdit: _scope.editQueued,
              onRemove: _scope.removeQueued,
              // While the agent works "Send next" resumes the queue for the end of the turn.
              onSendNext: _canSend(view) || view.status.isBusy ? _scope.sendNextQueued : null,
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _scope.unsavedGate.held,
            builder: (context, held, _) => held == 0
                ? const SizedBox.shrink()
                : ChatUnsavedFilesBar(
                    count: held,
                    onSaveAll: () => _scope.unsavedGate.saveAll().ignore(),
                    onSendAnyway: () => _scope.unsavedGate.sendAnyway().ignore(),
                  ),
          ),
          StateConsumer<FileMentionController, FileMentionState>(
            controller: _scope.fileMentionController,
            builder: (context, _, _) => ValueListenableBuilder<RunMentions?>(
              valueListenable: _scope.runContext,
              builder: (context, runContext, _) => ValueListenableBuilder<ChatSkills>(
                valueListenable: _scope.chatSkills,
                builder: (context, chatSkills, _) =>
                    StateConsumer<ChatSkillsController, ChatSkillsState>(
                      controller: _scope.chatSkillsController,
                      builder: (context, chatSkillsState, _) =>
                          ValueListenableBuilder<List<ComposerImage>>(
                            valueListenable: _scope.images,
                            builder: (context, images, _) => PromptComposer(
                              images: images,
                              onRemoveImage: _scope.removeImage,
                              onPasteImage: _scope.pasteImage,
                              runContext: runContext,
                              onAppCommand: _scope.widget.onAppCommand,
                              // The `/` menu offers the skills this chat has on.
                              chatSkills: chatSkills.forChat(_scope.chatSkillsController.states),
                              controller: _scope.textController,
                              focusNode: _scope.composerFocus,
                              canSend: _canSend(view),
                              canStop:
                                  view.status == SessionStatus.running ||
                                  view.status == SessionStatus.awaitingPermission,
                              stopping: view.status == SessionStatus.cancelling,
                              busy: view.status.isBusy,
                              onQueue: _scope.queue,
                              onSend: _scope.send,
                              onStop: _scope.stop,
                              mentionFiles: _scope.fileMentionController.files,
                              onMentionStart: _scope.refreshFiles,
                              commands: view.commands,
                              onAcceptPending: _answerPending(view.pendingPermission, accept: true),
                              onRejectPending: _answerPending(
                                view.pendingPermission,
                                accept: false,
                              ),
                              onCycleMode:
                                  view.canChangeConfig &&
                                      permissionModeOf(view.configOptions) != null
                                  ? _scope.cycleMode
                                  : null,
                              toolbar: <Widget>[
                                // Rebuilt when an agent's check changes its status.
                                StateConsumer<AgentsController, AgentsState>(
                                  controller: _scope.agentsController,
                                  builder: (context, _, _) => ComposerToolbar(
                                    agentName: agentDisplayName(
                                      view.agentId,
                                      _scope.agentsController.agents,
                                      Localization.of(context),
                                    ),
                                    agentId: view.agentId,
                                    agents: _scope.agentsController.agents,
                                    onAgentSelected: _scope.setAgent,
                                    agentLocked: !view.agentChangeable,
                                    options: view.configOptions,
                                    enabled: view.canChangeConfig,
                                    onChanged: _scope.setConfig,
                                    onAttach: _scope.attachFile,
                                    onMakeDefault: _scope.makeDefault,
                                    chatSkills: chatSkills,
                                    chatSkillStates: _scope.chatSkillsController.states,
                                    onToggleChatSkill: _scope.setChatSkill,
                                    onOpenSkillLibrary: _scope.canOpenSkills
                                        ? _scope.openSkills
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ),
              ),
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
