import 'package:meta/meta.dart';

/// One entry of the chat feed, folded from the journal by `ChatTranscript`.
@immutable
sealed class ChatItem {
  const ChatItem(this.seq);

  /// `seq` of the journal event that created the item (stable list key).
  final int seq;
}

/// A prompt the user sent.
final class UserMessageItem extends ChatItem {
  /// Creates a user message.
  const UserMessageItem(super.seq, {required this.text, this.resources = const <String>[]});

  /// Prompt text.
  final String text;

  /// Paths or URIs of attached files (`resource_link`).
  final List<String> resources;
}

/// Agent reply text (Markdown), merged from chunks with the same message id.
final class AgentMessageItem extends ChatItem {
  /// Creates an agent message.
  const AgentMessageItem(super.seq, {required this.text, this.messageId});

  /// Markdown text so far.
  final String text;

  /// ACP `messageId`, when the agent sends one.
  final String? messageId;
}

/// Agent reasoning (shown collapsed).
final class AgentThoughtItem extends ChatItem {
  /// Creates a thought.
  const AgentThoughtItem(super.seq, {required this.text, this.messageId, this.duration});

  /// Thought text so far.
  final String text;

  /// ACP `messageId`, when the agent sends one.
  final String? messageId;

  /// Time between the first and the last chunk; `null` for a single chunk.
  final Duration? duration;
}

/// Content of a tool call.
@immutable
sealed class ToolContent {
  const ToolContent();
}

/// Plain text produced by a tool.
final class ToolTextContent extends ToolContent {
  /// Creates text content.
  const ToolTextContent(this.text);

  /// The text.
  final String text;
}

/// A file change; [oldText] is `null` for a new file.
final class ToolDiffContent extends ToolContent {
  /// Creates a diff.
  const ToolDiffContent({required this.path, required this.newText, this.oldText});

  /// Absolute path of the file.
  final String path;

  /// Text before the change, `null` when the file is new.
  final String? oldText;

  /// Text after the change.
  final String newText;
}

/// A tool call (read, edit, run a command…), updated in place as it runs.
final class ToolCallItem extends ChatItem {
  /// Creates a tool call.
  const ToolCallItem(
    super.seq, {
    required this.toolCallId,
    required this.title,
    this.kind,
    this.status = 'pending',
    this.content = const <ToolContent>[],
    this.locations = const <String>[],
    this.rawOutput,
  });

  /// ACP `toolCallId`.
  final String toolCallId;

  /// Human-readable title.
  final String title;

  /// ACP tool kind (`read`, `edit`, `execute`, …).
  final String? kind;

  /// `pending`, `in_progress`, `completed` or `failed`.
  final String status;

  /// Text and diffs.
  final List<ToolContent> content;

  /// Files the tool touches.
  final List<String> locations;

  /// Raw tool output, shown on demand.
  final String? rawOutput;

  /// Diffs among [content].
  Iterable<ToolDiffContent> get diffs => content.whereType<ToolDiffContent>();

  /// Copy with the fields an update carries.
  ToolCallItem merge({
    String? title,
    String? kind,
    String? status,
    List<ToolContent>? content,
    List<String>? locations,
    String? rawOutput,
  }) => ToolCallItem(
    seq,
    toolCallId: toolCallId,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    content: content ?? this.content,
    locations: locations ?? this.locations,
    rawOutput: rawOutput ?? this.rawOutput,
  );
}

/// One step of the agent's plan.
@immutable
final class PlanEntry {
  /// Creates a plan entry.
  const PlanEntry({required this.content, required this.status});

  /// What the step does.
  final String content;

  /// `pending`, `in_progress` or `completed`.
  final String status;
}

/// The agent's current plan (replaced by later plan updates of the turn).
final class PlanItem extends ChatItem {
  /// Creates a plan.
  const PlanItem(super.seq, {required this.entries});

  /// Steps in order.
  final List<PlanEntry> entries;
}

/// An option the agent offers in a permission request.
@immutable
final class PermissionOptionView {
  /// Creates an option.
  const PermissionOptionView({required this.optionId, required this.name, required this.kind});

  /// `optionId` to answer with.
  final String optionId;

  /// Button label.
  final String name;

  /// `allow_once`, `allow_always`, `reject_once` or `reject_always`.
  final String kind;

  /// Whether the option allows the action.
  bool get allows => kind.startsWith('allow');
}

/// State of a permission request in the feed.
enum PermissionState {
  /// Waiting for the user.
  pending,

  /// The user picked an option.
  selected,

  /// Cancelled (Stop, the agent withdrew it, the app closed).
  cancelled,

  /// Left open when the app stopped; can no longer be answered.
  stale,
}

/// The agent asks before doing something.
final class PermissionItem extends ChatItem {
  /// Creates a permission request.
  const PermissionItem(
    super.seq, {
    required this.requestId,
    required this.title,
    required this.options,
    this.toolCallId,
    this.diffs = const <ToolDiffContent>[],
    this.command,
    this.state = PermissionState.pending,
    this.selectedOptionId,
  });

  /// Key to answer with.
  final String requestId;

  /// What the agent wants to do.
  final String title;

  /// Buttons.
  final List<PermissionOptionView> options;

  /// Tool call the request belongs to.
  final String? toolCallId;

  /// Proposed file changes, for edits.
  final List<ToolDiffContent> diffs;

  /// Shell command, for command runs.
  final String? command;

  /// Where the request stands.
  final PermissionState state;

  /// The option the user chose.
  final String? selectedOptionId;

  /// The option Enter picks: the first `allow_once`. Enter never grants a standing permission, so
  /// without one it does nothing.
  PermissionOptionView? get acceptOption =>
      options.where((o) => o.kind == 'allow_once').firstOrNull;

  /// The option Escape picks: the first `reject_once`, else the first one that does not allow.
  PermissionOptionView? get rejectOption =>
      rejectOnceOption ?? options.where((o) => !o.allows).firstOrNull;

  /// The first `reject_once`: a "not this time" decline, never a standing one.
  PermissionOptionView? get rejectOnceOption =>
      options.where((o) => o.kind == 'reject_once').firstOrNull;

  /// A copy in [state] (with the picked [optionId]).
  PermissionItem resolve(PermissionState state, {String? optionId}) => PermissionItem(
    seq,
    requestId: requestId,
    title: title,
    options: options,
    toolCallId: toolCallId,
    diffs: diffs,
    command: command,
    state: state,
    selectedOptionId: optionId,
  );
}

/// One file a turn changed.
@immutable
final class TurnFile {
  /// Creates a changed file.
  const TurnFile({required this.path, required this.status});

  /// Path relative to the repository root.
  final String path;

  /// Git status letters now (`??`, ` M`, `R `, ` D`) or `clean`.
  final String status;
}

/// Files a turn changed, including changes without a diff event (shell
/// commands, hooks, formatters). Git repositories only.
final class TurnFilesItem extends ChatItem {
  /// Creates the list.
  const TurnFilesItem(super.seq, {required this.files});

  /// Changed files, sorted by path.
  final List<TurnFile> files;
}

/// A turn ended in a way worth showing (cancelled, refused, limits hit).
final class TurnEndItem extends ChatItem {
  /// Creates a turn end marker.
  const TurnEndItem(super.seq, {required this.stopReason});

  /// ACP `stopReason`.
  final String stopReason;
}

/// A note from the app (errors, lost agent context).
final class SystemItem extends ChatItem {
  /// Creates a system note.
  const SystemItem(super.seq, {required this.type, this.message});

  /// `error`, `context_lost`, `invalid_transition`, …
  final String type;

  /// Details.
  final String? message;
}

/// An event the app does not understand (kept for diagnostics).
final class UnknownItem extends ChatItem {
  /// Creates an unknown item.
  const UnknownItem(super.seq, {required this.kind});

  /// Journal kind.
  final String kind;
}
