import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/agents/controller/agents_controller.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_login_methods_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_queue_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/chat_recovery_controller.dart';
import 'package:flutter_code_agent/src/feature/chat/controller/unsaved_files_gate.dart';
import 'package:flutter_code_agent/src/feature/chat/data/chat_repository.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_code_agent/src/feature/chat/models/drop_classification.dart';
import 'package:flutter_code_agent/src/feature/chat/models/queued_prompt.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_drop_target.dart';
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
import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_file.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/composer_image.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/run_mentions.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/skill_prompt.dart';
import 'package:flutter_code_agent/src/feature/session_config/controller/session_config_controller.dart';
import 'package:flutter_code_agent/src/feature/session_config/data/session_config_repository.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_roles.dart';
import 'package:flutter_code_agent/src/feature/sessions/controller/session_agent_controller.dart';
import 'package:flutter_code_agent/src/feature/sessions/data/sessions_repository.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/chat_skill_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/chat_skills_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/controller/skill_text_controller.dart';
import 'package:flutter_code_agent/src/feature/skills/models/chat_skills.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:pasteboard/pasteboard.dart';
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

/// Reads the image on the clipboard; `null` when it holds none (or holds text, which the field
/// pastes).
typedef ClipboardImageReader = Future<Uint8List?> Function();

Future<Uint8List?> _readPasteboardImage() async {
  // Copied text can come with a picture of itself (a PDF or TIFF of the selection): text wins.
  if (await Clipboard.hasStrings()) return null;
  return Pasteboard.image;
}

/// {@template chat_config_widget}
/// One chat: owns its controllers and the composer text.
/// {@endtemplate}
class ChatConfigWidget extends StatefulWidget {
  /// {@macro chat_config_widget}
  const ChatConfigWidget({
    required this.sessionId,
    required this.project,
    this.pickFile = _pickWithDialog,
    this.readClipboardImage = _readPasteboardImage,
    this.onHandle,
    this.onOpenChange,
    this.runContext,
    this.onAppCommand,
    this.chatSkills = ChatSkills.empty,
    this.onOpenSkills,
    super.key,
  });

  /// `sessions.id`.
  final int sessionId;

  /// The chat's project (kept current by the workspace).
  final Project project;

  /// Opens the file dialog for the attach button.
  final FilePicker pickFile;

  /// Reads an image from the clipboard for ⌘V.
  final ClipboardImageReader readClipboardImage;

  /// Called with a [ChatHandle] for every new view of the chat, after the frame (never during
  /// build).
  final ValueChanged<ChatHandle>? onHandle;

  /// Called with the absolute, normalized path of the file when the user clicks an edit row in the feed;
  /// `null` leaves the row as a plain expander.
  final ValueChanged<String>? onOpenChange;

  /// What the running app offers the `@` menu of the composer; `null` offers nothing. May change
  /// while the chat is open.
  final RunMentions? runContext;

  /// An app command (`run`, `reload`, `restart`, `screenshot`) was chosen in the `/` menu of the
  /// composer; `null` leaves the commands as text.
  final ValueChanged<String>? onAppCommand;

  /// The skills of the chat's project for the 🧩 chip, the `/` menu and the skill lines of the
  /// feed. May change while the chat is open.
  final ChatSkills chatSkills;

  /// Shows the skill library: on the skill [itemId] when given, for the chat's project. `null`
  /// hides the 🧩 chip and leaves the skill lines of the feed plain.
  final void Function({String? itemId, int? projectId})? onOpenSkills;

  @override
  State<ChatConfigWidget> createState() => ChatConfigWidgetState();
}

class ChatConfigWidgetState extends State<ChatConfigWidget> {
  late final ChatController chatController;
  late final AgentsController agentsController;
  late final SessionAgentController sessionAgentController;
  late final ChatRecoveryController recoveryController;
  late final ChatLoginMethodsController loginMethodsController;
  late final PromptSendingController promptController;
  late final PermissionAnswerController permissionController;
  late final SessionConfigController configController;
  late final FileMentionController fileMentionController;
  late final ChatSkillsController chatSkillsController;
  late final ChatSkillActionsController chatSkillActionsController;
  late final SkillTextController skillTextController;

  /// The chat's message queue; it outlives this widget while it holds messages.
  late final ChatQueueController queueController;
  late final ChatQueueRegistry _queues;
  final TextEditingController textController = TextEditingController();
  final FocusNode composerFocus = FocusNode();

  /// Holds a message back while the project has files unsaved in the Code view.
  late final UnsavedFilesGate unsavedGate;

  /// The images that go with the next message (dropped or pasted), as chips of the composer.
  final ValueNotifier<List<ComposerImage>> images = ValueNotifier<List<ComposerImage>>(
    const <ComposerImage>[],
  );

  /// The files and folders from outside the project that go with the next message, as cards of
  /// the composer.
  final ValueNotifier<List<ComposerFile>> files = ValueNotifier<List<ComposerFile>>(
    const <ComposerFile>[],
  );

  /// [ChatConfigWidget.runContext], as something the composer can listen to.
  late final ValueNotifier<RunMentions?> runContext = ValueNotifier<RunMentions?>(
    widget.runContext,
  );

  /// [ChatConfigWidget.chatSkills], as something the composer can listen to. Equal skills do not
  /// notify, so a library that emits the same content again rebuilds nothing.
  late final ValueNotifier<ChatSkills> chatSkills = ValueNotifier<ChatSkills>(widget.chatSkills);
  ChatView? _publishedView;
  bool _publishScheduled = false;

  int get sessionId => widget.sessionId;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    final hub = dependencies.agentHub;
    _queues = dependencies.chatQueues;
    queueController = _queues.acquire(sessionId);
    unsavedGate = UnsavedFilesGate(files: dependencies.codeViews, projectId: widget.project.id);
    // Assigned before it opens: [_followStatus] reads it on the first change.
    chatController = ChatController(
      repository: ChatRepositoryImpl(hub: hub, agents: dependencies.agentsRepository),
    );
    chatController
      ..addListener(_schedulePublish)
      ..addListener(_followStatus)
      ..open(sessionId);
    final chatRepository = ChatRepositoryImpl(hub: hub, agents: dependencies.agentsRepository);
    agentsController = AgentsController(repository: dependencies.agentsRepository)..watch();
    sessionAgentController = SessionAgentController(
      repository: SessionsRepositoryImpl(
        database: dependencies.database,
        hub: hub,
        queuedChats: dependencies.chatQueues,
      ),
    )..addListener(_onAgentChanged);
    recoveryController = ChatRecoveryController(repository: chatRepository);
    loginMethodsController = ChatLoginMethodsController(repository: chatRepository)..watch();
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
    chatSkillsController = ChatSkillsController(repository: dependencies.chatSkillsRepository);
    // Only the 🧩 chip shows the choices, so a chat without the chip does not watch them.
    if (canOpenSkills) chatSkillsController.watch(sessionId);
    chatSkillActionsController = ChatSkillActionsController(
      repository: dependencies.chatSkillsRepository,
    );
    skillTextController = SkillTextController(repository: dependencies.skillsRepository);
  }

  @override
  void dispose() {
    chatController
      ..removeListener(_schedulePublish)
      ..removeListener(_followStatus)
      ..dispose();
    // The queue keeps sending into this chat while it holds messages.
    _queues.release(sessionId);
    recoveryController.dispose();
    agentsController.dispose();
    sessionAgentController
      ..removeListener(_onAgentChanged)
      ..dispose();
    loginMethodsController.dispose();
    promptController.dispose();
    permissionController.dispose();
    configController.dispose();
    fileMentionController.dispose();
    chatSkillsController.dispose();
    chatSkillActionsController.dispose();
    skillTextController.dispose();
    unsavedGate.dispose();
    textController.dispose();
    composerFocus.dispose();
    images.dispose();
    files.dispose();
    runContext.dispose();
    chatSkills.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChatConfigWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    runContext.value = widget.runContext;
    chatSkills.value = widget.chatSkills;
    if (canOpenSkills) chatSkillsController.watch(sessionId);
  }

  /// The chat's agent was changed: the hub forgot the chat's runtime state, so it is loaded again;
  /// a refused change is told to the user.
  void _onAgentChanged() {
    switch (sessionAgentController.state) {
      case SessionAgent$CompletedState(:final sessionId) when sessionId == this.sessionId:
        chatController.open(sessionId, keepView: true);
      case SessionAgent$ErrorState(:final error):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(Localization.of(context).agentActionFailed('$error'))),
        );
      case _:
    }
  }

  /// Lets the queue follow the chat's live status (again, after the runtime state was replaced).
  void _followStatus() {
    if (chatController.status case final status?) queueController.follow(status);
  }

  /// Makes [agentId] run this chat; only possible before the first message.
  void setAgent(String agentId) => sessionAgentController.set(sessionId, agentId);

  /// Whether the skill library can be shown from the chat.
  bool get canOpenSkills => widget.onOpenSkills != null;

  /// Shows the skill library for the chat's project, on the skill [itemId] when given.
  void openSkills({String? itemId}) =>
      widget.onOpenSkills?.call(itemId: itemId, projectId: widget.project.id);

  /// Turns [skill] on or off for this chat only.
  void setChatSkill(ChatSkill skill, {required bool enabled}) => chatSkillActionsController.set(
    sessionId,
    skill.id,
    enabled: enabled,
    projectEnabled: skill.enabled,
  );

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
    if (!mounted) return;
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

  /// The `resource_link`s for the files [text] mentions: project files, and the screenshots the
  /// run offers (they live in `.dart_tool`, outside the file list). Only files that are still
  /// inside the project count.
  Future<List<Map<String, Object?>>> resourcesFor(String text) async {
    final known = <String>{...fileMentionController.files, ...?runContext.value?.attachable};
    final mentioned = await fileMentionController.insideProject(
      widget.project.path,
      mentionedFiles(text, known),
    );
    return resourceLinks(widget.project.path, mentioned);
  }

  /// The skills this chat works with: the ones on for its project, minus the ones the chat turned
  /// off.
  ChatSkills get skillsOfChat => chatSkills.value.forChat(chatSkillsController.states);

  /// What goes to the agent for the composer [text]: the text and the content blocks beside it.
  ///
  /// A leading `/<name>` of a built-in or user skill that is on for the chat sends the rest of the
  /// text (or `Use the <name> skill.`) with `SKILL.md` embedded as a resource: the agent does not
  /// find those skills on disk. The project's own skills (`.claude/skills`) and every other text
  /// go as typed, as does a command whose `SKILL.md` cannot be read. Mentioned files follow as
  /// `resource_link`s ([resourcesFor]), then, [withImages], the composer's [files] as links and its
  /// [images] as `image` blocks.
  Future<({String text, List<Map<String, Object?>> resources})> promptFor(
    String text, {
    bool withImages = true,
  }) async {
    // Taken now: the caller clears the images it sent.
    final attached = <Map<String, Object?>>[
      if (withImages) ...<Map<String, Object?>>[
        for (final file in files.value) file.toBlock(),
        for (final image in images.value) image.toBlock(),
      ],
    ];
    final blocks = <Map<String, Object?>>[...await resourcesFor(text), ...attached];
    final command = leadingCommand(text);
    final skill = command == null ? null : skillsOfChat.runnable(command.name);
    if (command == null || skill == null || skill.source == SkillSource.project) {
      return (text: text, resources: blocks);
    }
    final String markdown;
    try {
      markdown = await skillTextController.read(skill.id, projectRoot: projectRoot);
    } on Object {
      return (text: text, resources: blocks);
    }
    return (
      text: skillPromptText(skill.name, command.rest),
      resources: <Map<String, Object?>>[skillResource(skill.name, markdown), ...blocks],
    );
  }

  /// Takes [sent] out of [files]; one added while the message was prepared stays.
  void _clearFiles(List<ComposerFile> sent) {
    if (sent.isEmpty) return;
    files.value = <ComposerFile>[
      for (final file in files.value)
        if (!sent.contains(file)) file,
    ];
  }

  /// Adds [file] as a card; one already there is not added twice.
  void _addFile(ComposerFile file) {
    if (files.value.contains(file)) return;
    files.value = <ComposerFile>[...files.value, file];
  }

  /// Takes the card [file] out (its ✕).
  void removeFile(ComposerFile file) => files.value = <ComposerFile>[
    for (final kept in files.value)
      if (kept != file) kept,
  ];

  /// Takes [sent] out of [images]; one added while the message was prepared stays.
  void _clearImages(List<ComposerImage> sent) {
    if (sent.isEmpty) return;
    images.value = <ComposerImage>[
      for (final image in images.value)
        if (!sent.contains(image)) image,
    ];
  }

  /// The images cannot go to the chat's agent: says so and returns `true`.
  bool _refuseImagesForAgent() {
    if (images.value.isEmpty || _agentAcceptsImages) return false;
    _tell(Localization.of(context).imagesNotAccepted);
    return true;
  }

  /// Sends the composer text ([promptFor]); the first prompt in a folder asks for trust.
  Future<void> send() async {
    final text = textController.text.trim();
    // Images or cards alone are a message too.
    if ((text.isEmpty && images.value.isEmpty && files.value.isEmpty) || _refuseImagesForAgent()) {
      return;
    }
    if (unsavedGate.hold(send)) return;
    if (!widget.project.isTrusted) {
      final trusted = await ProjectTrustDialog.show(context, widget.project);
      if (!trusted || !mounted) return;
    }
    final attached = images.value;
    final cards = files.value;
    final prompt = await promptFor(text);
    if (!mounted) return;
    textController.clear();
    _clearImages(attached);
    _clearFiles(cards);
    promptController.send(sessionId, prompt.text, resources: prompt.resources);
  }

  /// Queues the composer text ([promptFor], as it is now) to go after the running turn; the
  /// first prompt in a folder asks for trust.
  Future<void> queue() async {
    final draft = textController.text.trim();
    // A second ⌘↵ while the first is being prepared would queue the same text again.
    if ((draft.isEmpty && images.value.isEmpty && files.value.isEmpty) ||
        _queueing ||
        _refuseImagesForAgent()) {
      return;
    }
    if (unsavedGate.hold(queue)) return;
    _queueing = true;
    try {
      if (!widget.project.isTrusted) {
        final trusted = await ProjectTrustDialog.show(context, widget.project);
        if (!trusted || !mounted) return;
      }
      final attached = images.value;
      final cards = files.value;
      // The images and cards are kept as such; their blocks are built when the message goes.
      final prompt = await promptFor(draft, withImages: false);
      if (!mounted) return;
      textController.clear();
      _clearImages(attached);
      _clearFiles(cards);
      queueController.add(
        QueuedPrompt(
          text: prompt.text,
          resources: prompt.resources,
          draft: prompt.text == draft ? null : draft,
          images: attached,
          files: cards,
        ),
      );
    } finally {
      _queueing = false;
    }
  }

  /// [queue] is preparing a message.
  bool _queueing = false;

  /// Takes the queued message at [index] out of the queue and back into the composer, its images
  /// back into the chips.
  void editQueued(int index) {
    final prompt = queueController.edit(index);
    if (prompt == null) return;
    if (prompt.typed.isNotEmpty) insertDraft(prompt.typed);
    prompt.files.forEach(_addFile);
    if (prompt.images.isEmpty) return;
    final all = <ComposerImage>[...images.value, ...prompt.images];
    images.value = all.take(kMaxComposerImages).toList();
    if (all.length > kMaxComposerImages) {
      _tell(Localization.of(context).imageLimit(kMaxComposerImages));
    }
  }

  void removeQueued(int index) => queueController.remove(index);

  void sendNextQueued() => queueController.sendNext();

  /// Stops the turn; its end pauses the queue.
  void stop() {
    queueController.pauseAfterStop();
    promptController.stop(sessionId).ignore();
  }

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
      _tell(Localization.of(context).attachOutsideProject);
      return;
    }
    _insertAtCaret('@${inside.single}');
    // The file list decides at send time which mentions become attachments.
    refreshFiles();
    composerFocus.requestFocus();
  }

  /// Puts [inserted] at the caret (in place of the selection), with a space before and after it
  /// unless one is already there, and moves the caret behind it and the space after it.
  void _insertAtCaret(String inserted) {
    final text = textController.text;
    final selection = textController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final space = RegExp(r'\s');
    final before = start > 0 && !space.hasMatch(text[start - 1]) ? ' ' : '';
    final spaceFollows = end < text.length && space.hasMatch(text[end]);
    final piece = '$before$inserted${spaceFollows ? '' : ' '}';
    textController.value = TextEditingValue(
      text: text.replaceRange(start, end, piece),
      // The caret goes past the space that was already there, as past the one added.
      selection: TextSelection.collapsed(offset: start + piece.length + (spaceFollows ? 1 : 0)),
    );
  }

  /// Files and folders dropped on the chat: project ones become `@mentions` and outside ones
  /// their absolute path, at the caret in drop order; images become chips.
  Future<void> drop(List<String> paths) async {
    final dropped = classifyDrop(paths, projectRoot: projectRoot);
    final texts = <String>[for (final path in dropped) ?path.text];
    if (texts.isNotEmpty) _insertAtCaret(texts.join(' '));
    if (dropped.any((path) => path is DropMention)) refreshFiles();
    for (final path in dropped) {
      if (path case DropAbsolute(:final path, :final folder)) {
        _addFile(ComposerFile(path: path, folder: folder));
      }
    }
    composerFocus.requestFocus();
    await _attachImageFiles(<String>[
      for (final path in dropped)
        if (path is DropImage) path.path,
    ]);
  }

  /// Adds the image files at [paths] as chips; the first refusal is told in one line.
  Future<void> _attachImageFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    final localization = Localization.of(context);
    String? refusal;
    for (final path in paths) {
      final name = p.basename(path);
      String? reason;
      try {
        final file = File(path);
        reason = _imageRefusal(localization, name, await file.length());
        if (reason == null) {
          final image = await ComposerImage.of(
            name: name,
            mimeType: composerImageType(path)!,
            bytes: await file.readAsBytes(),
          );
          if (!mounted) return;
          reason = _addImage(localization, image);
        }
        // A missing file, or one the engine cannot decode.
      } on Exception {
        reason = localization.imageUnreadable(name);
      }
      refusal ??= reason;
    }
    if (refusal != null && mounted) _tell(refusal);
  }

  /// ⌘V in the composer: the clipboard's image, if it holds one, becomes a chip.
  Future<void> pasteImage() async {
    final Uint8List? bytes;
    try {
      bytes = await widget.readClipboardImage();
    } on Object {
      return;
    }
    if (bytes == null || !mounted) return;
    const name = 'clipboard.png';
    final localization = Localization.of(context);
    // Checked before the thumbnail is made: a refused image is not decoded.
    var refusal = _imageRefusal(localization, name, bytes.length);
    if (refusal == null) {
      try {
        final image = await ComposerImage.of(name: name, mimeType: 'image/png', bytes: bytes);
        if (!mounted) return;
        refusal = _addImage(localization, image);
      } on Exception {
        refusal = localization.imageUnreadable(name);
      }
    }
    if (refusal != null && mounted) _tell(refusal);
  }

  /// Takes the chip of the image at [index] away.
  void removeImage(int index) {
    final list = images.value;
    if (index < 0 || index >= list.length) return;
    images.value = <ComposerImage>[...list]..removeAt(index);
  }

  /// The chat's agent takes images; an agent the app knows nothing about is not held back.
  bool get _agentAcceptsImages {
    final agentId = _view?.agentId;
    return agentsController.agents
            .where((agent) => agent.id == agentId)
            .firstOrNull
            ?.acceptsImages ??
        true;
  }

  /// Why an image of [size] bytes cannot be added now; `null` when it can.
  String? _imageRefusal(GeneratedLocalization localization, String name, int size) {
    if (!_agentAcceptsImages) return localization.imagesNotAccepted;
    if (images.value.length >= kMaxComposerImages) {
      return localization.imageLimit(kMaxComposerImages);
    }
    if (size > kMaxComposerImageBytes) {
      return localization.imageTooLarge(name, kMaxComposerImageBytes ~/ (1024 * 1024));
    }
    return null;
  }

  /// Adds [image] unless [_imageRefusal] says no; returns the refusal.
  String? _addImage(GeneratedLocalization localization, ComposerImage image) {
    final refusal = _imageRefusal(localization, image.name, image.bytes.length);
    if (refusal == null) images.value = <ComposerImage>[...images.value, image];
    return refusal;
  }

  /// One line at the bottom of the window.
  void _tell(String message) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));

  /// Allows bypass for this chat and sends the prompt that was held back.
  Future<void> allowBypass() async {
    await configController.acknowledgeBypass(sessionId);
    if (chatController.state case Chat$CompletedState(:final view) when view.canRetryPrompt) {
      repeatPrompt();
    }
  }

  /// Signs [agentId] in with [methodId]; a browser or key sign-in can be cancelled.
  void login(String agentId, String methodId) {
    final method = loginMethodsController
        .methodsOf(agentId)
        .where((m) => m.id == methodId)
        .firstOrNull;
    recoveryController.login(
      agentId,
      methodId,
      cancellable: method != null && method.kind != AgentLoginKind.terminal,
    );
  }

  /// Stops the running browser or key sign-in of [agentId].
  void cancelLogin(String agentId) => recoveryController.cancelLogin(agentId);

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
  Widget build(BuildContext context) => ChatConfigInhWidget(
    state: this,
    child: ChatDropTarget(
      events: Dependencies.of(context).dropZone,
      onDropped: drop,
      child: const ChatScreen(),
    ),
  );
}
