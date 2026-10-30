import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/run_mentions.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:path/path.dart' as p;

/// {@template workspace_run_link}
/// Ties the run of the selected project to the selected chat, and gives the window's run controls
/// (title bar, shortcuts) one place to act: start and stop, hot reload and restart, an error or
/// the picked widget into the composer, the offer for the `@` menu, and the hot reload after an
/// agent turn.
///
/// It never sends a message: everything it puts into the chat is a draft the user sends.
/// {@endtemplate}
class WorkspaceRunLink {
  /// {@macro workspace_run_link}
  WorkspaceRunLink({
    required this._data,
    required this._run,
    required this._actions,
    required this._reloadAfterTurn,
  }) {
    _data.chatHandle.addListener(_onChatHandle);
  }

  final WorkspaceDataController _data;
  final RunController _run;
  final RunActionsController _actions;
  final bool Function() _reloadAfterTurn;

  /// The chat whose status is followed (the selected one) and the last status seen for it, to tell
  /// a finished turn from a repeated status. Forgotten when the selection moves on, so a turn that
  /// ended while the chat was not open never reloads when it is opened again.
  int? _followedSession;
  SessionStatus? _lastStatus;

  /// Stops following the chat.
  void dispose() => _data.chatHandle.removeListener(_onChatHandle);

  /// The selected project when the run state is about it.
  int? get _projectId => _run.state.projectId == _data.projectId ? _data.projectId : null;

  /// Whether the app of the selected project is built and running (hot reload works).
  bool get isRunning => _projectId != null && _run.state.run is RunRunning;

  /// Whether the app of the selected project is building or running.
  bool get isActive => _projectId != null && (isRunning || _run.state.run is RunBuilding);

  /// Whether there is a device to start the app on.
  bool get canStart => _projectId != null && _run.state.selectedDeviceId != null;

  /// Starts the app of the selected project on the chosen device.
  void start() {
    final projectId = _projectId;
    final state = _run.state;
    final deviceId = state.selectedDeviceId;
    if (projectId == null || deviceId == null) return;
    _actions.start(projectId, deviceId: deviceId, mode: state.mode, target: state.target);
  }

  /// Stops the app of the selected project.
  void stop() {
    if (_projectId case final projectId?) _actions.stop(projectId);
  }

  /// Hot reloads the app; does nothing unless it is running.
  void reload() {
    if (isRunning) _actions.hotReload(_projectId!);
  }

  /// Hot restarts the app; does nothing unless it is running.
  void restart() {
    if (isRunning) _actions.hotRestart(_projectId!);
  }

  /// Puts the error of [entry] into the draft of the selected chat and marks the line as sent;
  /// `false` (nothing done) when no chat is selected.
  bool sendError(LogEntry entry) {
    final error = entry.error;
    final handle = _data.chatHandle.value;
    if (error == null) return true;
    if (handle == null) return false;
    handle.insertDraft(error.forAgent());
    _run.markSent(entry.seq);
    return true;
  }

  /// Puts [picked] into the draft of the selected chat; `false` when no chat is selected.
  bool addWidget(PickedWidget picked) {
    final handle = _data.chatHandle.value;
    if (handle == null) return false;
    handle.insertDraft(_widgetText(picked));
    return true;
  }

  /// What the app offers the `@` menu of the selected project's chats: the picked widget and the
  /// last error; `null` when it has neither.
  RunMentions? get mentions {
    final state = _run.state;
    if (state.projectId == null || state.projectId != _data.projectId) return null;
    final picked = state.picked;
    final error = state.logs.reversed.where((log) => log.error != null).firstOrNull?.error;
    if (picked == null && error == null) return null;
    return RunMentions(
      widget: picked == null
          ? null
          : RunMention(
              detail: '${picked.name} · ${p.basename(picked.file)}:${picked.line}',
              text: _widgetText(picked),
            ),
      error: error == null ? null : RunMention(detail: error.title, text: _errorText(error)),
    );
  }

  static String _widgetText(PickedWidget picked) =>
      '@widget ${picked.name} (${picked.file}:${picked.line})';

  static String _errorText(RunError error) {
    final place = error.location ?? (error.file == null ? null : '${error.file}:${error.line}');
    return '@error ${error.title}${place == null ? '' : ' ($place)'}';
  }

  /// A turn of the open chat ended (busy to idle): hot reload once, when the user wants that and
  /// the app runs. A status published again, or a chat that was never busy, reloads nothing.
  void _onChatHandle() {
    final handle = _data.chatHandle.value;
    if (handle == null) {
      _followedSession = null;
      _lastStatus = null;
      return;
    }
    final status = handle.view.status;
    final before = _followedSession == handle.sessionId ? _lastStatus : null;
    _followedSession = handle.sessionId;
    _lastStatus = status;
    final turnEnded =
        status == SessionStatus.idle &&
        (before == SessionStatus.running ||
            before == SessionStatus.awaitingPermission ||
            before == SessionStatus.cancelling);
    if (turnEnded && _reloadAfterTurn()) reload();
  }
}
