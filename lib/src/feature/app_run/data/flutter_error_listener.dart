import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:l/l.dart' show l;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// The runtime errors of a running app, as the framework reports them over its VM service.
abstract interface class IFlutterErrorListener {
  /// The errors the app reports from now on, and those that came before the first listen. Its
  /// [RunError.file] is the file as the app names it (a `file:` or `package:` URI); the run
  /// makes it project-relative. Ends with [close] or when the app goes away.
  Stream<RunError> errors();

  /// Stops listening and closes the connection. Calling it again does nothing.
  Future<void> close();
}

/// Connects an [IFlutterErrorListener] to the VM service at [vmServiceUri]; throws when the app
/// cannot report structured errors there.
typedef FlutterErrorListenerConnect = Future<IFlutterErrorListener> Function(Uri vmServiceUri);

/// The service extension that makes the framework post `Flutter.Error` events.
const String _structuredErrors = 'ext.flutter.inspector.structuredErrors';

/// {@template flutter_error_listener}
/// Listens to the `Flutter.Error` events of a debug app: it switches the framework's structured
/// errors on (`ext.flutter.inspector.structuredErrors`) in every isolate that registers the
/// extension — again after a hot restart, which starts a new isolate — and turns each event into a
/// [RunError] (see [runErrorFromFlutterError]).
///
/// With structured errors on the framework posts the error instead of printing it, so the output
/// of `flutter run` no longer holds the error block.
/// {@endtemplate}
final class FlutterErrorListener implements IFlutterErrorListener {
  FlutterErrorListener._(this._service);

  /// {@macro flutter_error_listener}
  ///
  /// Connects to the VM service at [vmServiceUri] and [attach]es to it.
  static Future<IFlutterErrorListener> connect(Uri vmServiceUri) async =>
      attach(await vmServiceConnectUri(vmServiceUri.toString()));

  /// {@macro flutter_error_listener}
  ///
  /// Completes once structured errors are on in the app; waits up to [extensionTimeout] for an app
  /// that has not registered the extension yet (a profile app never does) and throws a
  /// [TimeoutException] then. Throws what the service throws when the extension fails. [service]
  /// is the listener's from then on: [close] disposes it, and so does a failed attach.
  static Future<FlutterErrorListener> attach(
    VmService service, {
    Duration extensionTimeout = const Duration(seconds: 30),
  }) async {
    final listener = FlutterErrorListener._(service);
    try {
      await listener._start().timeout(extensionTimeout);
      return listener;
    } on Object {
      await listener._stop();
      rethrow;
    }
  }

  final VmService _service;
  final StreamController<RunError> _errors = StreamController<RunError>();
  final List<StreamSubscription<Object?>> _subscriptions = <StreamSubscription<Object?>>[];

  /// Completes once structured errors are on in an isolate.
  final Completer<void> _enabled = Completer<void>();
  bool _closed = false;

  Future<void> _start() async {
    // An isolate event may fail it before it is awaited below.
    _enabled.future.ignore();
    _subscriptions
      ..add(_service.onExtensionEvent.listen(_onExtension))
      ..add(_service.onIsolateEvent.listen(_onIsolate));
    unawaited(_service.onDone.then((_) => _stop()));
    await _service.streamListen(EventStreams.kExtension);
    await _service.streamListen(EventStreams.kIsolate);
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
      if (isolate.extensionRPCs?.contains(_structuredErrors) ?? false) await _enable(id);
    }
    await _enabled.future;
  }

  Future<void> _enable(String isolateId) async {
    await _service.callServiceExtension(
      _structuredErrors,
      isolateId: isolateId,
      args: <String, Object?>{'enabled': 'true'},
    );
    if (!_enabled.isCompleted) _enabled.complete();
  }

  void _onIsolate(Event event) {
    final id = event.isolate?.id;
    if (_closed || event.kind != EventKind.kServiceExtensionAdded || id == null) return;
    if (event.extensionRPC != _structuredErrors) return;
    _enable(id).catchError((Object error, StackTrace stackTrace) {
      // Before attach completes, a failure here fails it; later the errors stay in the output.
      if (!_enabled.isCompleted) {
        _enabled.completeError(error, stackTrace);
      } else if (!_closed) {
        l.w('FlutterErrorListener | cannot switch structured errors on in $id: $error');
      }
    }).ignore();
  }

  void _onExtension(Event event) {
    if (event.extensionKind != 'Flutter.Error' || _errors.isClosed) return;
    final data = event.extensionData?.data;
    if (data == null) return;
    _errors.add(runErrorFromFlutterError(Map<String, Object?>.from(data)));
  }

  @override
  Stream<RunError> errors() => _errors.stream;

  @override
  Future<void> close() => _stop();

  Future<void> _stop() async {
    if (_closed) return;
    _closed = true;
    if (!_enabled.isCompleted)
      _enabled.completeError(StateError('The VM service connection closed.'));
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _service.dispose();
    // Completes only once a listener took the done event, so it is not awaited.
    unawaited(_errors.close());
  }
}

/// The [RunError] of the `Flutter.Error` event data [data] (an inspector node of the error):
///
/// - the title is the error's summary (`A RenderFlex overflowed by 42 pixels on the right.`),
///   else its description;
/// - the message is `renderedErrorText` without the frame of `═` rules and without the stack
///   frames, which become the stack; after the first error since a reload the framework renders
///   only `Another exception was thrown: …`;
/// - the place is the first `creationLocation` of a node, one the inspector marks as the project's
///   (`createdByLocalProject`) first, else the place of "The relevant error-causing widget was".
RunError runErrorFromFlutterError(Map<String, Object?> data) {
  final nodes = _nodes(data).toList();
  final description = data['description'] is String ? data['description']! as String : '';
  final summary = nodes
      .where((node) => node['type'] == 'ErrorSummary' || node['level'] == 'summary')
      .map((node) => node['description'])
      .whereType<String>()
      .firstWhere((text) => text.trim().isNotEmpty, orElse: () => '');
  final title = summary.isNotEmpty
      ? summary
      : description.isNotEmpty
      ? description
      : 'Flutter error';

  final rendered = data['renderedErrorText'] is String ? data['renderedErrorText']! as String : '';
  final message = <String>[];
  final stack = <String>[];
  for (final line in rendered.split('\n')) {
    final trimmed = line.trimRight();
    if (_rule.hasMatch(trimmed)) continue;
    (_frame.hasMatch(trimmed) ? stack : message).add(trimmed);
  }
  final messageText = message.join('\n').trim();

  final place = _creationPlace(nodes) ?? _errorCausingWidgetPlace(nodes);
  return RunError(
    title: title,
    message: messageText.isEmpty ? title : messageText,
    file: place?.file,
    line: place?.line,
    location: place == null
        ? null
        : '${place.file.substring(place.file.lastIndexOf('/') + 1)}:${place.line}:${place.column}',
    stack: stack.isEmpty ? null : stack.join('\n'),
  );
}

/// The header `══╡ EXCEPTION CAUGHT BY … ╞═══` and the closing `═══` of a rendered error.
final RegExp _rule = RegExp(r'^═+(?:╡.*╞═*)?$');
final RegExp _frame = RegExp(r'^#\d+\s');
final RegExp _placeInText = RegExp(r'((?:file|package):\S+?\.dart):(\d+):(\d+)');

typedef _Place = ({String file, int line, int column});

/// [node] and every node below it, depth first: its properties, then its children.
Iterable<Map<String, Object?>> _nodes(Map<String, Object?> node) sync* {
  yield node;
  for (final key in const <String>['properties', 'children']) {
    if (node[key] case final List<Object?> list) {
      for (final child in list) {
        if (child is Map) yield* _nodes(Map<String, Object?>.from(child));
      }
    }
  }
}

_Place? _creationPlace(List<Map<String, Object?>> nodes) {
  _Place? first;
  for (final node in nodes) {
    final place = switch (node['creationLocation']) {
      {'file': final String file, 'line': final int line, 'column': final int column} => (
        file: file,
        line: line,
        column: column,
      ),
      _ => null,
    };
    if (place == null) continue;
    if (node['createdByLocalProject'] == true) return place;
    first ??= place;
  }
  return first;
}

_Place? _errorCausingWidgetPlace(List<Map<String, Object?>> nodes) {
  for (final node in nodes) {
    if (node['name'] != 'The relevant error-causing widget was') continue;
    for (final child in _nodes(node).skip(1)) {
      final match = _placeInText.firstMatch('${child['description'] ?? ''}');
      if (match != null) {
        return (
          file: match.group(1)!,
          line: int.parse(match.group(2)!),
          column: int.parse(match.group(3)!),
        );
      }
    }
  }
  return null;
}
