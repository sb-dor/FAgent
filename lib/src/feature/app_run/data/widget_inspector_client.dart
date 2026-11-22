import 'dart:async';
import 'dart:convert';

import 'package:flutter_code_agent/src/feature/app_run/models/inspector_node.dart';
import 'package:l/l.dart' show l;
import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Something the widget inspector of a running app did, seen from its VM service.
@immutable
sealed class InspectorEvent {
  const InspectorEvent(this.isolateId);

  /// The isolate the event came from.
  final String isolateId;

  @override
  bool operator ==(Object other) =>
      other is InspectorEvent && other.runtimeType == runtimeType && other.isolateId == isolateId;

  @override
  int get hashCode => Object.hash(runtimeType, isolateId);
}

/// The user picked a widget in the app (the `navigate` tool event of `flutter.inspector`).
final class InspectorNavigated extends InspectorEvent {
  /// Creates the event.
  const InspectorNavigated(super.isolateId);

  @override
  String toString() => 'InspectorNavigated($isolateId)';
}

/// The select mode of the app was switched, by [WidgetInspectorClient.setSelectMode] or by the user
/// in the app.
final class InspectorSelectModeChanged extends InspectorEvent {
  /// Creates the event.
  const InspectorSelectModeChanged(super.isolateId, this.enabled);

  /// Whether the select mode is on now.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      super == other && other is InspectorSelectModeChanged && other.enabled == enabled;

  @override
  int get hashCode => Object.hash(super.hashCode, enabled);

  @override
  String toString() => 'InspectorSelectModeChanged($isolateId, $enabled)';
}

/// An isolate of the app ended, for example at a hot restart; its object ids are gone.
final class InspectorIsolateExited extends InspectorEvent {
  /// Creates the event.
  const InspectorIsolateExited(super.isolateId);

  @override
  String toString() => 'InspectorIsolateExited($isolateId)';
}

/// The object group all the picker's inspector ids belong to.
const String kInspectorObjectGroup = 'flutter_code_agent_picker';

const String _show = 'ext.flutter.inspector.show';
const String _selectedSummaryWidget = 'ext.flutter.inspector.getSelectedSummaryWidget';
const String _parentChain = 'ext.flutter.inspector.getParentChain';
const String _screenshot = 'ext.flutter.inspector.screenshot';
const String _disposeGroup = 'ext.flutter.inspector.disposeGroup';

/// The stream of tool events (`navigate` when a widget is picked); `vm_service` has no constant.
const String _toolEventStream = 'ToolEvent';

/// {@template widget_inspector_client}
/// The widget inspector of a debug app, over its VM service: the select mode, the selected widget
/// and its parents, a picture of a widget.
///
/// A thin layer over `vm_service`, like the flutter error listener: it holds one connection, and
/// every method takes the isolate to ask, since a hot restart starts a new one ([inspectorIsolate]).
/// Errors are those of `vm_service`: an [RPCError] when the app fails a call, a
/// [SentinelException] when the isolate is gone.
/// {@endtemplate}
final class WidgetInspectorClient {
  /// {@macro widget_inspector_client}
  ///
  /// Listens to the events of [service] from now on; [close] disposes it.
  WidgetInspectorClient.attach(VmService service) : _service = service {
    _subscriptions
      ..add(_service.onEvent(_toolEventStream).listen(_onToolEvent))
      ..add(_service.onExtensionEvent.listen(_onExtension))
      ..add(_service.onIsolateEvent.listen(_onIsolate));
    unawaited(_service.onDone.then((_) => close()));
  }

  /// {@macro widget_inspector_client}
  ///
  /// Connects to the VM service at [vmServiceUri].
  static Future<WidgetInspectorClient> connect(Uri vmServiceUri) async =>
      WidgetInspectorClient.attach(await vmServiceConnectUri(vmServiceUri.toString()));

  final VmService _service;
  final List<StreamSubscription<Object?>> _subscriptions = <StreamSubscription<Object?>>[];
  late final StreamController<InspectorEvent> _events = StreamController<InspectorEvent>.broadcast(
    onListen: _onFirstListen,
  );
  Future<void>? _listening;
  bool _closed = false;

  /// What happens in the app's inspector: a pick, the select mode switching, an isolate ending.
  /// Broadcast; the VM streams behind it are listened to once, when the first listener comes or
  /// [setSelectMode] is called, whichever is first. Ends with [close] or when the app goes away.
  Stream<InspectorEvent> get events => _events.stream;

  void _onFirstListen() {
    _listen().catchError((Object error) {
      if (!_closed) l.w('WidgetInspectorClient | cannot listen to the app: $error');
    });
  }

  /// Starts the VM event streams, once.
  Future<void> _listen() => _listening ??= () async {
    await _service.streamListen(_toolEventStream);
    await _service.streamListen(EventStreams.kExtension);
    await _service.streamListen(EventStreams.kIsolate);
  }();

  /// The id of the first isolate that has the widget inspector (registers
  /// `ext.flutter.inspector.show`), or `null` when none has; ask again after a hot restart.
  Future<String?> inspectorIsolate() async {
    final vm = await _service.getVM();
    for (final ref in vm.isolates ?? const <IsolateRef>[]) {
      final id = ref.id;
      if (id == null) continue;
      final Isolate isolate;
      try {
        isolate = await _service.getIsolate(id);
      } on SentinelException {
        continue; // It exited in the meantime.
      }
      if (isolate.extensionRPCs?.contains(_show) ?? false) return id;
    }
    return null;
  }

  /// Switches the select mode of the app in [isolateId] on or off. Turning it off also clears the
  /// app's selection. Starts listening to the VM events first, so the pick that follows is seen.
  Future<void> setSelectMode(String isolateId, {required bool enabled}) async {
    await _listen();
    await _call(_show, isolateId, <String, Object?>{'enabled': enabled.toString()});
  }

  /// The widget selected in the app, from its summary tree (the user's own widgets); `null` when
  /// none is selected.
  Future<InspectorNode?> selectedWidget(String isolateId) async {
    final result = await _call(_selectedSummaryWidget, isolateId, <String, Object?>{
      'objectGroup': kInspectorObjectGroup,
    });
    final node = _result(result);
    return node is Map ? InspectorNode.fromJson(Map<String, Object?>.from(node)) : null;
  }

  /// The widgets from the root of the tree down to the one with inspector id [id], in that order.
  Future<List<InspectorNode>> parentChain(String isolateId, String id) async {
    final result = await _call(_parentChain, isolateId, <String, Object?>{
      'arg': id,
      'objectGroup': kInspectorObjectGroup,
    });
    final chain = _result(result);
    return <InspectorNode>[
      if (chain is List)
        for (final entry in chain)
          if (entry is Map && entry['node'] is Map)
            InspectorNode.fromJson(Map<String, Object?>.from(entry['node']! as Map)),
    ];
  }

  /// A PNG of the widget with inspector id [id], up to 800x800 at a pixel ratio of at most 2;
  /// `null` when the app could not take one.
  Future<List<int>?> screenshot(String isolateId, String id) async {
    final result = await _call(_screenshot, isolateId, <String, Object?>{
      'id': id,
      'width': '800',
      'height': '800',
      'maxPixelRatio': '2',
    });
    final png = result.json?['result'];
    return png is String ? base64Decode(png) : null;
  }

  /// Frees the inspector ids of the picker in the app in [isolateId].
  Future<void> disposeGroup(String isolateId) async {
    await _call(_disposeGroup, isolateId, <String, Object?>{'objectGroup': kInspectorObjectGroup});
  }

  /// Stops listening and closes the connection. Calling it again does nothing.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _service.dispose();
    // Completes only once a listener took the done event, so it is not awaited.
    unawaited(_events.close());
  }

  Future<Response> _call(String method, String isolateId, Map<String, Object?> args) =>
      _service.callServiceExtension(method, isolateId: isolateId, args: args);

  /// The `result` of an extension answer: the inspector wraps its payload in it, a JSON object or
  /// list, or a string of JSON in older versions.
  Object? _result(Response response) {
    final result = response.json?['result'];
    return result is String ? jsonDecode(result) : result;
  }

  void _onToolEvent(Event event) {
    final id = event.isolate?.id;
    if (_events.isClosed || id == null || event.extensionKind != 'navigate') return;
    if (event.extensionData?.data['source'] != 'flutter.inspector') return;
    _events.add(InspectorNavigated(id));
  }

  void _onExtension(Event event) {
    final id = event.isolate?.id;
    if (_events.isClosed || id == null) return;
    if (event.extensionKind != 'Flutter.ServiceExtensionStateChanged') return;
    final data = event.extensionData?.data;
    if (data == null || data['extension'] != _show) return;
    // The framework sends a bool; the string is tolerated.
    final value = data['value'];
    _events.add(InspectorSelectModeChanged(id, value == true || value == 'true'));
  }

  void _onIsolate(Event event) {
    final id = event.isolate?.id;
    if (_events.isClosed || id == null || event.kind != EventKind.kIsolateExit) return;
    _events.add(InspectorIsolateExited(id));
  }
}
