import 'package:meta/meta.dart';

/// Who produced a journal event.
enum SessionEventOrigin {
  /// The user (a prompt, a permission decision).
  user,

  /// The agent (a raw ACP frame).
  agent,

  /// The app itself (system notes, turn ends, changed files).
  app,
}

/// Journal event kinds written by the app (agent updates use their
/// `sessionUpdate` value as the kind).
abstract final class SessionEventKind {
  /// A prompt the user sent; payload is the `session/prompt` params.
  static const String prompt = 'prompt';

  /// The agent asked for permission; payload holds the request id and params.
  static const String permissionRequest = 'permission_request';

  /// How a permission request ended (selected option, cancelled, stale).
  static const String permissionResolution = 'permission_resolution';

  /// A note from the app (turn end, errors, lost context).
  static const String system = 'system';

  /// Files changed during a turn.
  static const String turnFiles = 'turn_files';
}

/// {@template session_event}
/// One row of a chat's journal.
/// {@endtemplate}
@immutable
final class SessionEvent {
  /// {@macro session_event}
  const SessionEvent({
    required this.seq,
    required this.origin,
    required this.kind,
    required this.payload,
    required this.createdAt,
  });

  /// Order inside the session.
  final int seq;

  /// Who produced the event.
  final SessionEventOrigin origin;

  /// `sessionUpdate` kind or one of [SessionEventKind].
  final String kind;

  /// Raw JSON.
  final Map<String, Object?> payload;

  /// When the event was created.
  final DateTime createdAt;

  @override
  String toString() => 'SessionEvent(#$seq ${origin.name} $kind)';
}
