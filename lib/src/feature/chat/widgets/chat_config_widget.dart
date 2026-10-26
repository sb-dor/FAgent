import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_recovery_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_screen.dart';
import 'package:flutter_code_agent/src/feature/file_mention/controller/file_mention_controller.dart';
import 'package:flutter_code_agent/src/feature/file_mention/data/project_files_repository.dart';
import 'package:flutter_code_agent/src/feature/file_mention/models/file_mention.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/permission_request/controller/permission_answer_controller.dart';
import 'package:flutter_code_agent/src/feature/permission_request/data/permission_answer_repository.dart';
import 'package:flutter_code_agent/src/feature/project_trust/widgets/project_trust_dialog.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/controller/prompt_sending_controller.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/data/prompt_sending_repository.dart';
import 'package:flutter_code_agent/src/feature/session_config/controller/session_config_controller.dart';
import 'package:flutter_code_agent/src/feature/session_config/data/session_config_repository.dart';

/// Gives the chat widgets access to [ChatConfigWidgetState].
class ChatConfigInhWidget extends InheritedWidget {
  const ChatConfigInhWidget({super.key, required this.state, required super.child});

  final ChatConfigWidgetState state;

  static ChatConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<ChatConfigInhWidget>()?.widget;
    assert(widget != null, 'ChatConfigInhWidget was not found in element tree');
    return (widget! as ChatConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(ChatConfigInhWidget oldWidget) => false;
}

/// {@template chat_config_widget}
/// One chat: owns its controllers and the composer text.
/// {@endtemplate}
class ChatConfigWidget extends StatefulWidget {
  /// {@macro chat_config_widget}
  const ChatConfigWidget({required this.sessionId, required this.project, super.key});

  /// `sessions.id`.
  final int sessionId;

  /// The chat's project (kept current by the workspace).
  final Project project;

  @override
  State<ChatConfigWidget> createState() => ChatConfigWidgetState();
}

class ChatConfigWidgetState extends State<ChatConfigWidget> {
  late final ChatController chatController;
  late final ChatRecoveryController recoveryController;
  late final PromptSendingController promptController;
  late final PermissionAnswerController permissionController;
  late final SessionConfigController configController;
  late final FileMentionController fileMentionController;
  final TextEditingController textController = TextEditingController();
  final FocusNode composerFocus = FocusNode();

  int get sessionId => widget.sessionId;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    final hub = dependencies.agentHub;
    chatController = ChatController(repository: ChatRepositoryImpl(hub: hub))..open(sessionId);
    recoveryController = ChatRecoveryController(repository: ChatRepositoryImpl(hub: hub));
    promptController = PromptSendingController(repository: PromptSendingRepositoryImpl(hub: hub));
    permissionController = PermissionAnswerController(
      repository: PermissionAnswerRepositoryImpl(hub: hub),
    );
    configController = SessionConfigController(repository: SessionConfigRepositoryImpl(hub: hub));
    fileMentionController = FileMentionController(
      repository: ProjectFilesRepositoryImpl(environment: dependencies.shellEnvironment),
    );
  }

  @override
  void dispose() {
    chatController.dispose();
    recoveryController.dispose();
    promptController.dispose();
    permissionController.dispose();
    configController.dispose();
    fileMentionController.dispose();
    textController.dispose();
    composerFocus.dispose();
    super.dispose();
  }

  /// Refreshes the file list (the agent may have added files).
  void refreshFiles() => fileMentionController.load(widget.project.path);

  /// Sends the composer text with the mentioned files as `resource_link`s;
  /// the first prompt in a folder asks for trust.
  Future<void> send() async {
    final text = textController.text.trim();
    if (text.isEmpty) return;
    if (!widget.project.isTrusted) {
      final trusted = await ProjectTrustDialog.show(context, widget.project);
      if (!trusted || !mounted) return;
    }
    final mentioned = mentionedFiles(text, fileMentionController.files.toSet());
    textController.clear();
    promptController.send(
      sessionId,
      text,
      resources: resourceLinks(widget.project.path, mentioned),
    );
  }

  void stop() => promptController.stop(sessionId).ignore();

  void forceStop(String agentId) => promptController.forceStop(agentId).ignore();

  void repeatPrompt() => promptController.repeat(sessionId);

  void answerPermission(String requestId, String optionId) =>
      permissionController.answer(sessionId: sessionId, requestId: requestId, optionId: optionId);

  void retry() => recoveryController.retry(sessionId);

  void setConfig(String configId, Object value) => configController.set(sessionId, configId, value);

  void allowBypass() => configController.acknowledgeBypass(sessionId);

  void login(String agentId) => recoveryController.login(agentId);

  /// Destructive; asks first.
  Future<void> startNewAgentSession() async {
    final localization = Localization.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localization.startNewAgentSession),
        content: Text(localization.startNewAgentSessionConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localization.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(localization.continueAction),
          ),
        ],
      ),
    );
    if (confirmed ?? false) recoveryController.startNewAgentSession(sessionId);
  }

  @override
  Widget build(BuildContext context) => ChatConfigInhWidget(state: this, child: const ChatScreen());
}
