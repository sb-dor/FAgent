import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_inspector_client.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/inspector_node.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:l/l.dart' show l;
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart' show RPCError, RPCErrorKind, SentinelException;

/// How many of the project's widgets around the picked one a pick reports.
const int kPickedAncestorLimit = 8;

/// How long turning the select mode off may take before the pick ends without it (the app may be
/// gone already).
const Duration _selectModeOffTimeout = Duration(seconds: 2);

/// {@template widget_picker_repository_impl}
/// Picks widgets in a debug app through its widget inspector, over a [WidgetInspectorClient] of its
/// own (not DevTools, the Dart MCP server or the run's connection).
///
/// One client per project: opened at the first pick from the run's `vmServiceUri`, closed when the
/// run leaves [RunRunning] or moves to another address (it follows [IAppRunRepository.watchRun]),
/// when the connection drops (the next pick opens a new one) and at [dispose]. A project's picks
/// never touch another project's app.
///
/// A pick releases the inspector ids of the one before (the object group), turns the select mode
/// on and waits for the tap; the user leaving the select mode in the app, [cancel], a hot restart
/// and the end of the run end it as [PickCancelled]. The select mode is always turned off again.
/// {@endtemplate}
final class WidgetPickerRepositoryImpl implements IWidgetPickerRepository {
  /// {@macro widget_picker_repository_impl}
  ///
  /// [projectRoot] gives the folder of a project (`null` when it is unknown): files are made
  /// relative to it and the widget's PNG goes into it. [connect] opens the client for a VM
  /// service address.
  WidgetPickerRepositoryImpl({
    required this._runs,
    required this._projectRoot,
    this._connect = WidgetInspectorClient.connect,
  });

  final IAppRunRepository _runs;
  final Future<String?> Function(int projectId) _projectRoot;
  final Future<WidgetInspectorClient> Function(Uri vmServiceUri) _connect;

  final Map<int, _ProjectPicker> _projects = <int, _ProjectPicker>{};
  bool _disposed = false;

  _ProjectPicker _project(int projectId) =>
      _projects.putIfAbsent(projectId, () => _ProjectPicker(projectId));

  @override
  Future<PickResult> pick(int projectId) async {
    if (_disposed) return const PickCancelled();
    final project = _project(projectId);
    // One pick at a time: a new one ends the one that waits, and starts once that turned the
    // select mode off.
    for (var previous = project.pick; previous != null; previous = project.pick) {
      previous.cancel();
      await previous.done;
    }
    if (_disposed) return const PickCancelled();
    final pick = _Pick();
    project.pick = pick;
    try {
      return await _runPick(project, pick);
    } finally {
      if (identical(project.pick, pick)) project.pick = null;
      pick.finish();
    }
  }

  Future<PickResult> _runPick(_ProjectPicker project, _Pick pick) async {
    final run = _runs.currentRun(project.projectId);
    final uri = run is RunRunning && run.mode == BuildMode.debug ? run.vmServiceUri : null;
    if (uri == null) return const PickFailed(PickFailed.notDebug);
    final WidgetInspectorClient client;
    try {
      client = await _client(project, uri);
    } on Object catch (error, stackTrace) {
      if (pick.cancelled) return const PickCancelled();
      l.w('WidgetPicker | cannot connect to the app of ${project.projectId}: $error', stackTrace);
      return const PickFailed(PickFailed.connectionLost);
    }
    if (pick.cancelled) return const PickCancelled();
    String? isolateId;
    try {
      isolateId = await client.inspectorIsolate();
      if (isolateId == null) return const PickFailed(PickFailed.inspectorUnavailable);
      pick.isolateId = isolateId;
      // The ids of the last pick go with the group.
      project.chain = null;
      await client.disposeGroup(isolateId);
      if (pick.cancelled) return const PickCancelled();
      await client.setSelectMode(isolateId, enabled: true);
      // Only now does the select mode turning off mean the user left it: the app echoes every
      // `show` call, this one included.
      pick.armed = true;
      await pick.tapped;
      pick.armed = false;
      if (pick.lost) return const PickFailed(PickFailed.connectionLost);
      if (pick.cancelled) return const PickCancelled();
      final node = await client.selectedWidget(isolateId);
      if (node == null || !node.local || node.fileUri == null) return const PickNoProjectWidget();
      return PickPicked(await _read(project, client, isolateId, node));
    } on Object catch (error, stackTrace) {
      return _failure(project, pick, error, stackTrace);
    } finally {
      pick.armed = false;
      if (isolateId != null && !pick.lost) await _selectModeOff(client, isolateId);
    }
  }

  @override
  Future<void> cancel(int projectId) async {
    final pick = _projects[projectId]?.pick;
    if (pick == null) return;
    pick.cancel();
    await pick.done;
  }

  @override
  Future<PickResult> select(int projectId, String id) async {
    final project = _projects[projectId];
    final chain = project?.chain;
    final client = project?.client;
    if (project == null || chain == null || client == null || !chain.ids.contains(id)) {
      return const PickGone();
    }
    try {
      final nodes = await client.parentChain(chain.isolateId, id);
      final node = nodes.where((node) => node.id == id).lastOrNull;
      if (node == null || node.fileUri == null) return const PickGone();
      return PickPicked(await _read(project, client, chain.isolateId, node, chain: nodes));
    } on SentinelException {
      return const PickGone();
    } on RPCError catch (error) {
      // The app no longer knows the id; or it is gone altogether.
      return _isConnectionLoss(error)
          ? const PickFailed(PickFailed.connectionLost)
          : const PickGone();
    } on Object catch (error, stackTrace) {
      l.w('WidgetPicker | cannot select $id in the app of $projectId: $error', stackTrace);
      return const PickFailed(PickFailed.connectionLost);
    }
  }

  /// The [PickedWidget] of [node]: its project-relative place, the project's widgets around it
  /// ([chain], or the app's parent chain of it) and a PNG of it. Remembers the ids for [select].
  Future<PickedWidget> _read(
    _ProjectPicker project,
    WidgetInspectorClient client,
    String isolateId,
    InspectorNode node, {
    List<InspectorNode>? chain,
  }) async {
    final root = await _projectRoot(project.projectId);
    final nodes = chain ?? await client.parentChain(isolateId, node.id);
    final ancestors = <PickedAncestor>[
      for (final ancestor in nodes.reversed)
        if (ancestor.local && ancestor.fileUri != null && ancestor.id != node.id)
          PickedAncestor(
            name: ancestor.name,
            file: _file(root, ancestor.fileUri!),
            line: ancestor.line ?? 0,
            column: ancestor.column ?? 0,
            id: ancestor.id,
          ),
    ].take(kPickedAncestorLimit).toList(growable: false);
    final known = project.chain;
    project.chain = (
      isolateId: isolateId,
      ids: <String>{
        if (known != null && known.isolateId == isolateId) ...known.ids,
        node.id,
        for (final ancestor in ancestors) ancestor.id,
      },
    );
    final png = await client.screenshot(isolateId, node.id);
    String? screenshot;
    if (png != null && root != null) {
      try {
        screenshot = await saveScreenshotPng(root, png, name: 'widget-${_fileSafe(node.name)}');
      } on io.FileSystemException catch (error, stackTrace) {
        l.w('WidgetPicker | cannot save the PNG of ${node.name}: $error', stackTrace);
      }
    }
    return PickedWidget(
      name: node.name,
      file: _file(root, node.fileUri!),
      line: node.line ?? 0,
      column: node.column ?? 0,
      ancestors: ancestors,
      id: node.id,
      screenshot: screenshot,
    );
  }

  PickResult _failure(_ProjectPicker project, _Pick pick, Object error, StackTrace stackTrace) {
    if (pick.lost) return const PickFailed(PickFailed.connectionLost);
    // A pick ended from outside (cancel, a stop, a restart) may fail on the way out.
    if (pick.cancelled) return const PickCancelled();
    if (error is SentinelException) return const PickCancelled(); // The isolate exited.
    if (error is! RPCError || _isConnectionLoss(error)) {
      l.w('WidgetPicker | lost the app of ${project.projectId}: $error', stackTrace);
      return const PickFailed(PickFailed.connectionLost);
    }
    l.w('WidgetPicker | the inspector of ${project.projectId} failed: $error', stackTrace);
    return PickFailed('The widget inspector failed: ${error.message}');
  }

  /// Turns the select mode of [isolateId] off, if the app still answers.
  Future<void> _selectModeOff(WidgetInspectorClient client, String isolateId) async {
    try {
      await client.setSelectMode(isolateId, enabled: false).timeout(_selectModeOffTimeout);
    } on Object catch (error) {
      l.v6('WidgetPicker | cannot turn the select mode off: $error');
    }
  }

  /// The project's client for [uri], connecting when there is none (or one for another address).
  Future<WidgetInspectorClient> _client(_ProjectPicker project, Uri uri) async {
    if (project.client case final client? when project.uri == uri) return client;
    // The pick that asks is not ended.
    await _close(project, endPick: false);
    final client = await _connect(uri);
    if (_disposed) {
      await client.close();
      throw StateError('The picker was disposed.');
    }
    project
      ..client = client
      ..uri = uri
      ..events = client.events.listen(
        (event) => _onEvent(project, event),
        onDone: () => _onConnectionDone(project, client),
      )
      ..run = _runs
          .watchRun(project.projectId)
          .listen(
            (state) => _onRun(project, client, state),
            onError: (Object error, StackTrace stackTrace) =>
                l.w('WidgetPicker | cannot follow the run of ${project.projectId}: $error'),
          );
    return client;
  }

  void _onEvent(_ProjectPicker project, InspectorEvent event) {
    final pick = project.pick;
    switch (event) {
      case InspectorNavigated(:final isolateId):
        if (pick != null && pick.isolateId == isolateId) pick.navigated();
      case InspectorSelectModeChanged(:final isolateId, enabled: false):
        if (pick != null && pick.armed && pick.isolateId == isolateId) pick.cancel();
      case InspectorSelectModeChanged():
        break;
      case InspectorIsolateExited(:final isolateId):
        if (project.chain?.isolateId == isolateId) project.chain = null;
        if (pick != null && pick.isolateId == isolateId) pick.cancel();
    }
  }

  /// The connection of [client] went away from the app's side ([_close] forgets the client first).
  /// When the run ended with it, a pick is cancelled as for a stop; otherwise it failed.
  void _onConnectionDone(_ProjectPicker project, WidgetInspectorClient client) {
    if (!identical(project.client, client)) return;
    final run = _runs.currentRun(project.projectId);
    final pick = project.pick;
    if (pick != null) {
      if (run is RunRunning && run.vmServiceUri == project.uri) {
        pick.connectionLost();
      } else {
        pick.cancel();
      }
    }
    unawaited(_close(project));
  }

  void _onRun(_ProjectPicker project, WidgetInspectorClient client, RunState state) {
    if (!identical(project.client, client)) return;
    if (state is RunRunning && state.vmServiceUri == project.uri) return;
    unawaited(_close(project));
  }

  /// Forgets the project's client at once, so the next pick connects again; then ends the
  /// project's pick unless [endPick] is `false` (it turns the select mode off while it still can)
  /// and closes the client.
  Future<void> _close(_ProjectPicker project, {bool endPick = true}) async {
    final client = project.client;
    project
      ..client = null
      ..uri = null
      ..chain = null;
    final stopped = project.stopFollowing();
    if (endPick) {
      if (project.pick case final pick?) {
        pick.cancel();
        await pick.done;
      }
    }
    await stopped;
    await client?.close();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait<void>(<Future<void>>[
      for (final project in _projects.values.toList()) _close(project),
    ]);
    _projects.clear();
  }

  /// [fileUri] as a path relative to [root] when it is a file in it; the path itself (or the URI,
  /// when it is not a file) otherwise.
  static String _file(String? root, String fileUri) {
    final uri = Uri.tryParse(fileUri);
    if (uri == null || !uri.isScheme('file')) return fileUri;
    final path = uri.toFilePath();
    if (root == null || !p.isWithin(root, path)) return path;
    return p.posix.joinAll(p.split(p.relative(path, from: root)));
  }

  /// [name] with only `[A-Za-z0-9_]` left (`Foo<Bar>` → `FooBar`); `widget` when nothing is.
  static String _fileSafe(String name) {
    final safe = name.replaceAll(RegExp('[^A-Za-z0-9_]'), '');
    return safe.isEmpty ? 'widget' : safe;
  }

  static bool _isConnectionLoss(RPCError error) =>
      error.code == RPCErrorKind.kServiceDisappeared.code ||
      error.code == RPCErrorKind.kConnectionDisposed.code ||
      error.message == 'Service connection disposed';
}

/// One pick in flight.
final class _Pick {
  final Completer<void> _tap = Completer<void>();
  final Completer<void> _done = Completer<void>();

  /// The isolate the select mode was turned on in; `null` until it is known.
  String? isolateId;

  /// Whether the select mode is on for this pick, so that it turning off is the user's doing.
  bool armed = false;

  /// Whether the pick was ended from outside: [cancel], the user leaving the select mode, a hot
  /// restart, the end of the run.
  bool cancelled = false;

  /// Whether the connection to the app went away during the pick.
  bool lost = false;

  /// Completes when the user tapped a widget or the pick was ended from outside.
  Future<void> get tapped => _tap.future;

  /// Completes once the pick returned, its select mode turned off.
  Future<void> get done => _done.future;

  void navigated() {
    if (!_tap.isCompleted) _tap.complete();
  }

  void cancel() {
    cancelled = true;
    if (!_tap.isCompleted) _tap.complete();
  }

  void connectionLost() {
    lost = true;
    cancel();
  }

  void finish() {
    if (!_tap.isCompleted) _tap.complete();
    if (!_done.isCompleted) _done.complete();
  }
}

/// What the picker holds for one project.
final class _ProjectPicker {
  _ProjectPicker(this.projectId);

  final int projectId;

  /// The connection to the app, and the address it is for.
  WidgetInspectorClient? client;
  Uri? uri;
  StreamSubscription<InspectorEvent>? events;
  StreamSubscription<RunState>? run;

  /// The pick in flight.
  _Pick? pick;

  /// Stops listening to the client's events and to the run at once; completes once both are
  /// cancelled.
  Future<void> stopFollowing() {
    final stopped = Future.wait<void>(<Future<void>>[?events?.cancel(), ?run?.cancel()]);
    events = null;
    run = null;
    return stopped;
  }

  /// The inspector ids [IWidgetPickerRepository.select] takes: those of the last pick and the
  /// selects after it, in the isolate they belong to. `null` once the group is released.
  ({String isolateId, Set<String> ids})? chain;
}
