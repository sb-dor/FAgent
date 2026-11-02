import 'dart:async';
import 'dart:convert';

import 'package:vm_service/vm_service.dart';

/// The service extension that switches structured errors on.
const String structuredErrorsExtension = 'ext.flutter.inspector.structuredErrors';

/// The service extension that switches the widget inspector's select mode.
const String inspectorShowExtension = 'ext.flutter.inspector.show';

/// The inspector extensions [ScriptedVmService] answers, as an isolate that has the widget inspector
/// registers them.
const List<String> inspectorExtensions = <String>[
  inspectorShowExtension,
  'ext.flutter.inspector.getSelectedSummaryWidget',
  'ext.flutter.inspector.getParentChain',
  'ext.flutter.inspector.screenshot',
  'ext.flutter.inspector.disposeGroup',
];

/// A [VmService] whose other side is driven by the test: it answers `streamListen`, `getVM`,
/// `getIsolate`, the structured errors extension and the widget inspector extensions, and
/// [emitFlutterError] and friends post events.
///
/// [isolates] maps an isolate id to the service extensions it has registered.
final class ScriptedVmService {
  /// Creates the service with [isolates] (id → extensions) already running.
  ScriptedVmService({Map<String, List<String>>? isolates})
    : isolates =
          isolates ??
          <String, List<String>>{
            'isolates/1': <String>[structuredErrorsExtension],
          } {
    service = VmService(_in.stream, _onMessage, disposeHandler: () async => disposed = true);
  }

  /// The isolates by id, with their service extensions.
  final Map<String, List<String>> isolates;

  /// The client side, as the code under test sees it.
  late final VmService service;

  /// Every request the code under test sent: its method and params.
  final List<({String method, Map<String, Object?> params})> requests =
      <({String method, Map<String, Object?> params})>[];

  /// When set, the structured errors extension answers with this error code.
  int? extensionErrorCode;

  /// When set, every widget inspector extension answers with this error code.
  int? inspectorErrorCode;

  /// What `getSelectedSummaryWidget` answers as `result`: a node as the inspector serializes it, or
  /// `null` when nothing is selected (see [inspectorNode]).
  Map<String, Object?>? selectedSummaryWidget;

  /// What `getParentChain` answers as `result`, root first (see [inspectorChainEntry]).
  List<Object?> parentChain = <Object?>[];

  /// What `screenshot` answers as `result`: a base64 PNG, or `null` when the shot failed.
  String? screenshotResult;

  /// Whether the client side was disposed.
  bool disposed = false;

  final StreamController<String> _in = StreamController<String>();

  /// The isolates the structured errors extension was switched on in, in order.
  List<String> get enabledIn => <String>[
    for (final request in requests)
      if (request.method == structuredErrorsExtension && request.params['enabled'] == 'true')
        request.params['isolateId']! as String,
  ];

  /// The params of every request to [method], in order.
  List<Map<String, Object?>> requestsTo(String method) => <Map<String, Object?>>[
    for (final request in requests)
      if (request.method == method) request.params,
  ];

  void _onMessage(String message) {
    final request = jsonDecode(message) as Map<String, Object?>;
    final id = request['id'];
    final method = request['method']! as String;
    final params = Map<String, Object?>.from(
      request['params'] as Map? ?? const <String, Object?>{},
    );
    requests.add((method: method, params: params));
    switch (method) {
      case 'streamListen':
        _respond(id, <String, Object?>{'type': 'Success'});
      case 'getVM':
        _respond(id, <String, Object?>{
          'type': 'VM',
          'name': 'vm',
          'isolates': <Object?>[for (final isolate in isolates.keys) _isolateRef(isolate)],
        });
      case 'getIsolate':
        final isolateId = params['isolateId']! as String;
        _respond(id, <String, Object?>{
          ..._isolateRef(isolateId),
          'type': 'Isolate',
          'extensionRPCs': isolates[isolateId] ?? const <String>[],
        });
      case structuredErrorsExtension:
        if (extensionErrorCode case final code?) {
          _send(<String, Object?>{
            'jsonrpc': '2.0',
            'id': id,
            'error': <String, Object?>{'code': code, 'message': 'Extension failed'},
          });
        } else {
          _respond(id, <String, Object?>{
            'type': '_extensionType',
            'method': method,
            'enabled': params['enabled'],
          });
        }
      case inspectorShowExtension:
        _inspector(id, method, <String, Object?>{'enabled': params['enabled'] ?? 'false'});
      case 'ext.flutter.inspector.getSelectedSummaryWidget':
        _inspector(id, method, <String, Object?>{'result': selectedSummaryWidget});
      case 'ext.flutter.inspector.getParentChain':
        _inspector(id, method, <String, Object?>{'result': parentChain});
      case 'ext.flutter.inspector.screenshot':
        _inspector(id, method, <String, Object?>{'result': screenshotResult});
      case 'ext.flutter.inspector.disposeGroup':
        _inspector(id, method, <String, Object?>{'result': null});
      default:
        _send(<String, Object?>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, Object?>{'code': -32601, 'message': 'Method not found'},
        });
    }
  }

  /// Answers an inspector extension with [result], or with [inspectorErrorCode] when set.
  void _inspector(Object? id, String method, Map<String, Object?> result) {
    if (inspectorErrorCode case final code?) {
      _send(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': code, 'message': 'Extension failed'},
      });
    } else {
      _respond(id, <String, Object?>{'type': '_extensionType', 'method': method, ...result});
    }
  }

  static Map<String, Object?> _isolateRef(String id) => <String, Object?>{
    'type': '@Isolate',
    'id': id,
    'name': 'main',
    'number': id.split('/').last,
    'isSystemIsolate': false,
  };

  void _respond(Object? id, Map<String, Object?> result) =>
      _send(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result});

  void _send(Map<String, Object?> message) {
    if (!_in.isClosed) _in.add(jsonEncode(message));
  }

  void _event(String streamId, Map<String, Object?> event) => _send(<String, Object?>{
    'jsonrpc': '2.0',
    'method': 'streamNotify',
    'params': <String, Object?>{
      'streamId': streamId,
      'event': <String, Object?>{'type': 'Event', 'timestamp': 0, ...event},
    },
  });

  /// Posts an `Extension` event of [kind] with [data] from [isolateId].
  void emitExtension(String kind, Map<String, Object?> data, {String isolateId = 'isolates/1'}) =>
      _event(EventStreams.kExtension, <String, Object?>{
        'kind': EventKind.kExtension,
        'extensionKind': kind,
        'extensionData': data,
        'isolate': _isolateRef(isolateId),
      });

  /// Posts a `ToolEvent` stream event of [kind] with [data] from [isolateId], as the framework posts
  /// `navigate` when a widget is picked.
  void emitToolEvent(String kind, Map<String, Object?> data, {String isolateId = 'isolates/1'}) =>
      _event('ToolEvent', <String, Object?>{
        'kind': EventKind.kExtension,
        'extensionKind': kind,
        'extensionData': data,
        'isolate': _isolateRef(isolateId),
      });

  /// Posts the `navigate` tool event the inspector posts when a widget is picked.
  void emitNavigate({
    String isolateId = 'isolates/1',
    String source = 'flutter.inspector',
    String fileUri = 'file:///p/app/lib/main.dart',
    int line = 14,
    int column = 18,
  }) => emitToolEvent('navigate', <String, Object?>{
    'fileUri': fileUri,
    'line': line,
    'column': column,
    'source': source,
  }, isolateId: isolateId);

  /// Posts the event the framework posts when the select mode changes. [value] is a `bool`, as the
  /// framework sends it.
  void emitSelectModeChanged(Object? value, {String isolateId = 'isolates/1'}) => emitExtension(
    'Flutter.ServiceExtensionStateChanged',
    <String, Object?>{'extension': inspectorShowExtension, 'value': value},
    isolateId: isolateId,
  );

  /// Posts `IsolateExit` for [isolateId] and forgets the isolate.
  void exitIsolate(String isolateId) {
    isolates.remove(isolateId);
    _event(EventStreams.kIsolate, <String, Object?>{
      'kind': EventKind.kIsolateExit,
      'isolate': _isolateRef(isolateId),
    });
  }

  /// Posts a `Flutter.Error` event with [data].
  void emitFlutterError(Map<String, Object?> data, {String isolateId = 'isolates/1'}) =>
      emitExtension('Flutter.Error', data, isolateId: isolateId);

  /// Registers [extension] in [isolateId] and posts `ServiceExtensionAdded`.
  void addExtension(String isolateId, String extension) {
    (isolates[isolateId] ??= <String>[]).add(extension);
    _event(EventStreams.kIsolate, <String, Object?>{
      'kind': EventKind.kServiceExtensionAdded,
      'extensionRPC': extension,
      'isolate': _isolateRef(isolateId),
    });
  }

  /// Ends the connection from the VM side.
  Future<void> disconnect() => _in.close();
}

/// A widget node as `getSelectedSummaryWidget` and `getParentChain` serialize it (trimmed to what
/// the picker reads). A [file] of `null` leaves `creationLocation` out, as for a widget without one.
Map<String, Object?> inspectorNode(
  String name, {
  String valueId = 'inspector-1',
  String? file = 'file:///p/app/lib/main.dart',
  int line = 14,
  int column = 18,
  bool local = true,
}) => <String, Object?>{
  'description': name,
  'type': 'DiagnosticableTreeNode',
  'valueId': valueId,
  'summaryTree': true,
  'createdByLocalProject': local,
  if (file != null)
    'creationLocation': <String, Object?>{'file': file, 'line': line, 'column': column},
};

/// An entry of the `getParentChain` result: [node] with the siblings the DevTools tree needs, which
/// the picker ignores.
Map<String, Object?> inspectorChainEntry(Map<String, Object?> node, {int childIndex = 0}) =>
    <String, Object?>{
      'node': node,
      'children': <Object?>[node],
      'childIndex': childIndex,
    };

/// A `Flutter.Error` event of a `RenderFlex` that overflowed by 42 pixels, created by a `Row` at
/// [file]:14:18, as a debug app on macOS posts it (trimmed: the render object's properties are
/// left out).
Map<String, Object?> overflowFlutterError({
  String file = 'file:///p/app/lib/main.dart',
  int errorsSinceReload = 0,
}) => <String, Object?>{
  'description': 'Exception caught by rendering library',
  'type': '_FlutterErrorDetailsNode',
  'allowWrap': false,
  'valueId': 'inspector-0',
  'errorsSinceReload': errorsSinceReload,
  'properties': <Object?>[
    <String, Object?>{
      'description': 'The following assertion was thrown during layout:',
      'type': 'ErrorDescription',
      'style': 'flat',
      'properties': <Object?>[],
      'children': <Object?>[],
    },
    <String, Object?>{
      'description': 'A RenderFlex overflowed by 42 pixels on the right.',
      'type': 'ErrorSummary',
      'level': 'summary',
      'style': 'flat',
      'properties': <Object?>[],
      'children': <Object?>[],
    },
    <String, Object?>{
      'description': '',
      'type': 'ErrorSpacer',
      'name': '',
      'style': 'singleLine',
      'properties': <Object?>[],
      'children': <Object?>[],
    },
    <String, Object?>{
      'description': '',
      'type': 'DiagnosticsBlock',
      'name': 'The relevant error-causing widget was',
      'style': 'whitespace',
      'properties': <Object?>[],
      'children': <Object?>[
        <String, Object?>{
          'description': 'Row Row:$file:14:18',
          'type': 'ErrorDescription',
          'style': 'flat',
          'properties': <Object?>[],
          'children': <Object?>[],
        },
      ],
    },
    <String, Object?>{
      'description': 'The overflowing RenderFlex has an orientation of Axis.horizontal.',
      'type': 'ErrorDescription',
      'style': 'flat',
      'properties': <Object?>[],
      'children': <Object?>[],
    },
    <String, Object?>{
      'description': 'RenderFlex#fbbbc relayoutBoundary=up3 OVERFLOWING',
      'type': 'DiagnosticableTreeNode',
      'name': 'The specific RenderFlex in question is',
      'style': 'shallow',
      'properties': <Object?>[],
      'children': <Object?>[],
    },
  ],
  'children': <Object?>[],
  'renderedErrorText': errorsSinceReload > 0
      ? 'Another exception was thrown: A RenderFlex overflowed by 42 pixels on the right.'
      : '''
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════════════════════════════════════════
The following assertion was thrown during layout:
A RenderFlex overflowed by 42 pixels on the right.

The relevant error-causing widget was:
  Row
  Row:$file:14:18

The overflowing RenderFlex has an orientation of Axis.horizontal.
The specific RenderFlex in question is: RenderFlex#fbbbc relayoutBoundary=up3 OVERFLOWING:
  size: Size(100.0, 20.0)
◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤
════════════════════════════════════════════════════════════════════════════════════════════════════''',
};

/// The overflow block `flutter run` prints for [overflowFlutterError] when structured errors are
/// off, one line per entry, behind the `flutter: ` prefix of macOS.
List<String> overflowBlockLines({String file = 'file:///p/app/lib/main.dart'}) => <String>[
  for (final line in (overflowFlutterError(file: file)['renderedErrorText']! as String).split('\n'))
    'flutter: $line',
];
