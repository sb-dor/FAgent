import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/build_mode.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/run_mentions.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:path/path.dart' as p;

/// {@template workspace_run_link}
/// Ties the run of the selected project to the selected chat, and gives the window's run controls
/// (title bar, shortcuts) one place to act: start and stop, hot reload and restart, an error, the
/// picked widget or a screenshot into the composer, the offer for the `@` menu, and the hot reload
/// after an agent turn.
///
/// It never sends a message: everything it puts into the chat is a draft the user sends. It
/// notifies when the offer for the `@` menu changes without the run changing (a new screenshot, a
/// picked widget).
/// {@endtemplate}
class WorkspaceRunLink extends ChangeNotifier {
  /// {@macro workspace_run_link}
  WorkspaceRunLink({
    required this._data,
    required this._run,
    required this._actions,
    required this._reloadAfterTurn,
    this._selectedDevice = _noDevice,
    this.isPreview = false,
    this._now = DateTime.now,
  }) {
    _data.chatHandle.addListener(_onChatHandle);
    _actions.pick.addListener(notifyListeners);
  }

  final WorkspaceDataController _data;
  final RunController _run;
  final RunActionsController _actions;
  final bool Function() _reloadAfterTurn;

  /// The chosen device as the device list has it; `null` when none is chosen or it is not listed.
  final Device? Function() _selectedDevice;

  static Device? _noDevice() => null;

  /// Gives the time a screenshot is taken at.
  final DateTime Function() _now;

  /// Every screenshot taken in this session, per project, oldest first.
  final Map<int, List<({String path, DateTime time})>> _screenshots =
      <int, List<({String path, DateTime time})>>{};

  /// Whether the run data is made up; the `@` menu says so.
  final bool isPreview;

  /// The chat whose status is followed (the selected one) and the last status seen for it, to tell
  /// a finished turn from a repeated status. Forgotten when the selection moves on, so a turn that
  /// ended while the chat was not open never reloads when it is opened again.
  int? _followedSession;
  SessionStatus? _lastStatus;

  /// Stops following the chat and the picker.
  @override
  void dispose() {
    _data.chatHandle.removeListener(_onChatHandle);
    _actions.pick.removeListener(notifyListeners);
    super.dispose();
  }

  /// The selected project when the run state is about it.
  int? get _projectId => _run.state.projectId == _data.projectId ? _data.projectId : null;

  /// Whether the app of the selected project is built and running (hot reload works).
  bool get isRunning => _projectId != null && _run.state.run is RunRunning;

  /// Whether the app of the selected project is building or running.
  bool get isActive => _projectId != null && (isRunning || _run.state.run is RunBuilding);

  /// Whether the chosen device is an emulator that is still booting; the app cannot start on it yet.
  bool get isLaunching => _projectId != null && _selectedDevice()?.kind == DeviceKind.available;

  /// Whether there is a device to start the app on: one is chosen, listed and running.
  bool get canStart => _projectId != null && _selectedDevice()?.kind == DeviceKind.running;

  /// Starts the app of the selected project on the chosen device.
  void start() {
    final projectId = _projectId;
    final state = _run.state;
    final device = _selectedDevice();
    if (projectId == null || device == null || device.kind != DeviceKind.running) return;
    _actions.start(
      projectId,
      device: device,
      mode: state.mode,
      target: state.target,
      arguments: state.arguments,
    );
  }

  /// Whether the app can be started from the composer: a running device is chosen and the app of
  /// the selected project is neither building nor running (the Run button is then not a Stop button).
  bool get _canStartNow => canStart && !isActive;

  /// Whether the app runs in debug: hot reload and restart need the JIT, and the inspector
  /// (screenshots) exists in debug only.
  bool get _runsInDebug => switch (_run.state.run) {
    RunRunning(:final mode) => _projectId != null && mode == BuildMode.debug,
    _ => false,
  };

  /// Whether the app can be hot reloaded or restarted: it runs in debug.
  bool get canReload => _runsInDebug;

  /// Whether a screenshot can be taken: the app runs in debug (the inspector exists in debug only).
  bool get canScreenshot => _runsInDebug;

  /// Does the app command [name] (`run`, `reload`, `restart` or `screenshot`) the `/` menu of the
  /// composer chose; an unknown name or a command that cannot work now does nothing.
  void runCommand(String name) {
    switch (name) {
      case 'run':
        if (_canStartNow) start();
      case 'reload':
        reload();
      case 'restart':
        restart();
      case 'screenshot':
        screenshot();
    }
  }

  /// Takes a screenshot of the running app of the selected project; does nothing unless it runs in
  /// debug. The path goes into the draft when the shot is ready (the window hands it to
  /// [addScreenshot]).
  void screenshot() {
    if (canScreenshot) _actions.screenshot(_projectId!);
  }

  /// Stops the app of the selected project.
  void stop() {
    if (_projectId case final projectId?) _actions.stop(projectId);
  }

  /// Hot reloads the app; does nothing unless it runs in debug. A pick that waits is cancelled,
  /// unless [cancelPick] is `false` (the reload after an agent turn leaves it be).
  void reload({bool cancelPick = true}) {
    if (canReload) _actions.hotReload(_projectId!, cancelPick: cancelPick);
  }

  /// Hot restarts the app; does nothing unless it runs in debug.
  void restart() {
    if (canReload) _actions.hotRestart(_projectId!);
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

  /// Puts [picked] into the draft of the selected chat: the `@widget` line, the line of its
  /// ancestors and the `@path` of its screenshot, each when there is one. The screenshot is
  /// remembered for the `@` menu and the send like the app's screenshots, even without a chat.
  /// `false` when no chat is selected.
  bool addWidget(PickedWidget picked) {
    final projectId = _data.projectId;
    if (picked.screenshot case final path? when projectId != null) _remember(projectId, path);
    final handle = _data.chatHandle.value;
    if (handle == null) return false;
    handle.insertDraft(
      <String>[
        _widgetText(picked),
        if (picked.ancestors.isNotEmpty)
          'in: ${picked.ancestors.map((ancestor) => ancestor.name).join(' › ')}',
        if (picked.screenshot case final path?) _screenshotText(path),
      ].join('\n'),
    );
    return true;
  }

  /// Remembers the screenshot [path] (relative to the project) that was taken for [projectId] and
  /// puts `@path` into the draft of the selected chat. `false` when the screenshot is for the
  /// selected project and no chat is selected (the path is remembered all the same, so the `@`
  /// menu offers it).
  bool addScreenshot(int projectId, String path) {
    _remember(projectId, path);
    if (projectId != _data.projectId) return true;
    final handle = _data.chatHandle.value;
    if (handle == null) return false;
    handle.insertDraft(_screenshotText(path));
    return true;
  }

  /// Remembers the PNG [path] (relative to the project) of [projectId] for the `@` menu.
  void _remember(int projectId, String path) {
    _screenshots.putIfAbsent(projectId, () => <({String path, DateTime time})>[])
      ..removeWhere((shot) => shot.path == path)
      ..add((path: path, time: _now()));
    notifyListeners();
  }

  /// What the app offers the selected project's chats: the picked widget, the last error and the
  /// last screenshot for the `@` menu, and what the `/` app commands can do now; `null` only when
  /// the run is not about the selected project.
  RunMentions? get mentions {
    final state = _run.state;
    if (state.projectId == null || state.projectId != _data.projectId) return null;
    final pick = _actions.pick.value;
    final picked = pick.projectId == state.projectId ? pick.widget : null;
    final error = state.logs.reversed.where((log) => log.error != null).firstOrNull?.error;
    final shots = _screenshots[state.projectId] ?? const <({String path, DateTime time})>[];
    return RunMentions(
      isPreview: isPreview,
      canStart: _canStartNow,
      isRunning: isRunning,
      canReload: canReload,
      canScreenshot: canScreenshot,
      screenshot: shots.isEmpty
          ? null
          : RunMention(detail: _clock(shots.last.time), text: _screenshotText(shots.last.path)),
      attachable: <String>{for (final shot in shots) shot.path},
      widget: picked == null
          ? null
          : RunMention(
              detail: '${picked.name} · ${p.basename(picked.file)}:${picked.line}',
              text: _widgetText(picked),
            ),
      error: error == null ? null : RunMention(detail: error.title, text: _errorText(error)),
    );
  }

  static String _screenshotText(String path) => '@$path';

  /// `HH:mm:ss`.
  static String _clock(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  /// `@widget Name (file:line:column)`; without the column when it is not known.
  static String _widgetText(PickedWidget picked) {
    final column = picked.column > 0 ? ':${picked.column}' : '';
    return '@widget ${picked.name} (${picked.file}:${picked.line}$column)';
  }

  static String _errorText(RunError error) {
    final place = error.place;
    return '@error ${error.title}${place == null ? '' : ' ($place)'}';
  }

  /// A turn of the open chat ended (busy to idle): hot reload once, when the user wants that and
  /// the app runs in debug. A status published again, or a chat that was never busy, reloads
  /// nothing.
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
    if (turnEnded && _reloadAfterTurn()) reload(cancelPick: false);
  }
}
