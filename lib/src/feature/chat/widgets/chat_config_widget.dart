import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_recovery_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
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
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_roles.dart';
import 'package:path/path.dart' as p;

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

/// Lets the user pick a file, starting in [initialDirectory]; `null` when they cancel.
typedef FilePicker = Future<String?> Function(String initialDirectory);

Future<String?> _pickWithDialog(String initialDirectory) async =>
    (await openFile(initialDirectory: initialDirectory))?.path;

/// {@template chat_config_widget}
/// One chat: owns its controllers and the composer text.
/// {@endtemplate}
class ChatConfigWidget extends StatefulWidget {
  /// {@macro chat_config_widget}
  const ChatConfigWidget({
    required this.sessionId,
    required this.project,
    this.pickFile = _pickWithDialog,
    this.onHandle,
    this.onOpenChange,
    super.key,
  });

  /// `sessions.id`.
  final int sessionId;

  /// The chat's project (kept current by the workspace).
  final Project project;

  /// Opens the file dialog for the attach button.
  final FilePicker pickFile;

  /// Called with a [ChatHandle] for every new view of the chat, after the frame (never during
  /// build).
  final ValueChanged<ChatHandle>? onHandle;

  /// Called with the absolute path of the file when the user clicks an edit row in the feed;
  /// `null` leaves the row as a plain expander.
  final ValueChanged<String>? onOpenChange;

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
  ChatView? _publishedView;
  bool _publishScheduled = false;

  int get sessionId => widget.sessionId;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    final hub = dependencies.agentHub;
    chatController = ChatController(repository: ChatRepositoryImpl(hub: hub))
      ..addListener(_schedulePublish)
      ..open(sessionId);
    recoveryController = ChatRecoveryController(repository: ChatRepositoryImpl(hub: hub));
    promptController = PromptSendingController(repository: PromptSendingRepositoryImpl(hub: hub));
    permissionController = PermissionAnswerController(
      repository: PermissionAnswerRepositoryImpl(hub: hub),
    );
    configController = SessionConfigController(
      repository: SessionConfigRepositoryImpl(
        hub: hub,
        settings: AppSettingsRepositoryImpl(database: dependencies.database),
      ),
    );
    fileMentionController = FileMentionController(
      repository: ProjectFilesRepositoryImpl(environment: dependencies.shellEnvironment),
    );
  }

  @override
  void dispose() {
    chatController
      ..removeListener(_schedulePublish)
      ..dispose();
    recoveryController.dispose();
    promptController.dispose();
    permissionController.dispose();
    configController.dispose();
    fileMentionController.dispose();
    textController.dispose();
    composerFocus.dispose();
    super.dispose();
  }

  /// Hands the latest view to [ChatConfigWidget.onHandle] once the frame is done; several views
  /// in one frame publish only the last.
  void _schedulePublish() {
    if (_publishScheduled || widget.onHandle == null) return;
    _publishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      final view = _view;
      final onHandle = widget.onHandle;
      if (!mounted || view == null || onHandle == null || identical(view, _publishedView)) return;
      _publishedView = view;
      onHandle(ChatHandle(sessionId: sessionId, view: view, insertDraft: insertDraft));
    });
  }

  /// Appends [text] to the composer, after a blank line when it already holds something, puts
  /// the caret at the end and focuses the composer.
  void insertDraft(String text) {
    final existing = textController.text;
    final combined = existing.isEmpty ? text : '$existing\n\n$text';
    textController.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );
    composerFocus.requestFocus();
  }

  /// Tells the owner that the user opened the edit of [path]; `null` when nobody listens.
  ValueChanged<String>? get onOpenChange => widget.onOpenChange;

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
    final mentioned = await fileMentionController.insideProject(
      widget.project.path,
      mentionedFiles(text, fileMentionController.files.toSet()),
    );
    if (!mounted) return;
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

  /// Declines [item] with its `reject_once` option (never a standing `reject_always`) and moves
  /// the caret to the composer, so the user can tell the agent what to do instead.
  void rejectAndSay(PermissionItem item) {
    final reject = item.rejectOption;
    if (reject == null) return;
    answerPermission(item.requestId, reject.optionId);
    composerFocus.requestFocus();
  }

  /// Folder of the chat's project.
  String get projectRoot => widget.project.path;

  void retry() => recoveryController.retry(sessionId);

  void setConfig(String configId, Object value) => configController.set(sessionId, configId, value);

  ChatView? get _view => switch (chatController.state) {
    Chat$CompletedState(:final view) => view,
    _ => null,
  };

  /// Switches to the next permission mode (Shift+Tab); never to `bypassPermissions`.
  void cycleMode() {
    final view = _view;
    if (view == null || !view.canChangeConfig) return;
    final mode = permissionModeOf(view.configOptions);
    final next = mode == null ? null : nextCycleMode(mode);
    if (mode != null && next != null) setConfig(mode.id, next);
  }

  /// Stores the chat's model, effort and mode as the start of new chats of its agent.
  void makeDefault() {
    final view = _view;
    if (view != null) configController.saveDefaults(view.agentId, defaultsOf(view.configOptions));
  }

  /// Lets the user pick a file and inserts `@path` at the caret. Only files inside the project
  /// can be mentioned.
  Future<void> attachFile() async {
    final root = widget.project.path;
    final picked = await widget.pickFile(root);
    if (picked == null || !mounted) return;
    final relative = p.relative(picked, from: root);
    final inside = await fileMentionController.insideProject(root, <String>[relative]);
    if (!mounted) return;
    if (inside.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(Localization.of(context).attachOutsideProject)));
      return;
    }
    final text = textController.text;
    final selection = textController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final separator = start > 0 && !RegExp(r'\s').hasMatch(text[start - 1]) ? ' ' : '';
    final inserted = '$separator@${inside.single} ';
    textController.value = TextEditingValue(
      text: text.replaceRange(start, end, inserted),
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
    // The file list decides at send time which mentions become attachments.
    refreshFiles();
    composerFocus.requestFocus();
  }

  /// Allows bypass for this chat and sends the prompt that was held back.
  Future<void> allowBypass() async {
    await configController.acknowledgeBypass(sessionId);
    if (chatController.state case Chat$CompletedState(:final view) when view.canRetryPrompt) {
      repeatPrompt();
    }
  }

  List<String> loginMethods(String agentId) => recoveryController.loginMethods(agentId);

  void login(String agentId, String methodId) => recoveryController.login(agentId, methodId);

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
