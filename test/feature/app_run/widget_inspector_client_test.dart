import 'dart:async';
import 'dart:convert';

import 'package:flutter_code_agent/src/feature/app_run/data/widget_inspector_client.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/inspector_node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

import '../../support/scripted_vm_service.dart';

void main() {
  group('WidgetInspectorClient', () {
    late ScriptedVmService vm;
    late WidgetInspectorClient client;

    setUp(() {
      vm = ScriptedVmService(isolates: <String, List<String>>{'isolates/1': inspectorExtensions});
      client = WidgetInspectorClient.attach(vm.service);
    });

    tearDown(() => client.close());

    test('finds the isolate with the inspector', () async {
      vm = ScriptedVmService(
        isolates: <String, List<String>>{
          'isolates/1': <String>['ext.dart.io.getVersion'],
          'isolates/2': inspectorExtensions,
        },
      );
      client = WidgetInspectorClient.attach(vm.service);

      expect(await client.inspectorIsolate(), 'isolates/2');
    });

    test('no isolate with the inspector gives null', () async {
      vm = ScriptedVmService(
        isolates: <String, List<String>>{
          'isolates/1': <String>[structuredErrorsExtension],
        },
      );
      client = WidgetInspectorClient.attach(vm.service);

      expect(await client.inspectorIsolate(), isNull);
    });

    test('setSelectMode sends show with enabled true/false', () async {
      await client.setSelectMode('isolates/1', enabled: true);
      await client.setSelectMode('isolates/1', enabled: false);

      expect(vm.requestsTo(inspectorShowExtension), <Map<String, Object?>>[
        <String, Object?>{'isolateId': 'isolates/1', 'enabled': 'true'},
        <String, Object?>{'isolateId': 'isolates/1', 'enabled': 'false'},
      ]);
    });

    test('listens to the tool, extension and isolate streams once', () async {
      final events = <InspectorEvent>[];
      client.events.listen(events.add);
      client.events.listen(events.add);
      await client.setSelectMode('isolates/1', enabled: true);
      await client.setSelectMode('isolates/1', enabled: false);

      expect(
        vm.requestsTo('streamListen').map((params) => params['streamId']),
        unorderedEquals(<String>['ToolEvent', EventStreams.kExtension, EventStreams.kIsolate]),
      );
    });

    group('events', () {
      late List<InspectorEvent> events;

      setUp(() async {
        events = <InspectorEvent>[];
        client.events.listen(events.add);
        // Waits for the streams to be listened to.
        await client.setSelectMode('isolates/1', enabled: true);
      });

      Future<void> settle() => pumpEventQueue();

      test('navigate event of flutter.inspector becomes InspectorNavigated, other sources are '
          'ignored', () async {
        vm
          ..emitNavigate(source: 'dart.devtools')
          ..emitToolEvent('somethingElse', <String, Object?>{'source': 'flutter.inspector'})
          ..emitNavigate(isolateId: 'isolates/2');
        await settle();

        expect(events, <InspectorEvent>[const InspectorNavigated('isolates/2')]);
      });

      test('show state change to false becomes InspectorSelectModeChanged(false)', () async {
        vm.emitSelectModeChanged(false);
        await settle();

        expect(events, <InspectorEvent>[const InspectorSelectModeChanged('isolates/1', false)]);
      });

      test('show state change to true becomes InspectorSelectModeChanged(true), a string value '
          'too', () async {
        vm
          ..emitSelectModeChanged(true)
          ..emitSelectModeChanged('false');
        await settle();

        expect(events, <InspectorEvent>[
          const InspectorSelectModeChanged('isolates/1', true),
          const InspectorSelectModeChanged('isolates/1', false),
        ]);
      });

      test('a state change of another extension is ignored', () async {
        vm
          ..emitExtension('Flutter.ServiceExtensionStateChanged', <String, Object?>{
            'extension': 'ext.flutter.inspector.trackRepaintWidgets',
            'value': false,
          })
          ..emitExtension('Flutter.Error', <String, Object?>{});
        await settle();

        expect(events, isEmpty);
      });

      test('isolate exit becomes InspectorIsolateExited', () async {
        vm.exitIsolate('isolates/1');
        await settle();

        expect(events, <InspectorEvent>[const InspectorIsolateExited('isolates/1')]);
      });

      test('the events can be listened to by many', () async {
        final other = <InspectorEvent>[];
        client.events.listen(other.add);
        vm.emitNavigate();
        await settle();

        expect(events, <InspectorEvent>[const InspectorNavigated('isolates/1')]);
        expect(other, events);
      });
    });

    test('selectedWidget parses name, id, creation location and local', () async {
      vm.selectedSummaryWidget = inspectorNode(
        'BookingCard',
        valueId: 'inspector-7',
        file: 'file:///p/app/lib/booking/booking_card.dart',
        line: 42,
        column: 7,
      );

      final node = await client.selectedWidget('isolates/1');

      expect(
        node,
        const InspectorNode(
          name: 'BookingCard',
          id: 'inspector-7',
          fileUri: 'file:///p/app/lib/booking/booking_card.dart',
          line: 42,
          column: 7,
          local: true,
        ),
      );
    });

    test('selectedWidget gives null when nothing is selected', () async {
      vm.selectedSummaryWidget = null;

      expect(await client.selectedWidget('isolates/1'), isNull);
    });

    test('a node without a creation location or the local flag has neither', () {
      final node = InspectorNode.fromJson(<String, Object?>{
        'description': 'Text',
        'valueId': 'inspector-3',
      });

      expect(node, const InspectorNode(name: 'Text', id: 'inspector-3'));
      expect(node.local, isFalse);
      expect(node.fileUri, isNull);
    });

    test('parentChain keeps order and parses each node', () async {
      vm.parentChain = <Object?>[
        inspectorChainEntry(inspectorNode('MyApp', valueId: 'inspector-1', line: 3, column: 1)),
        inspectorChainEntry(
          inspectorNode('Scaffold', valueId: 'inspector-2', file: null, local: false),
        ),
        inspectorChainEntry(inspectorNode('BookingCard', valueId: 'inspector-3', line: 42)),
      ];

      final chain = await client.parentChain('isolates/1', 'inspector-3');

      expect(chain.map((node) => node.name), <String>['MyApp', 'Scaffold', 'BookingCard']);
      expect(chain.map((node) => node.id), <String>['inspector-1', 'inspector-2', 'inspector-3']);
      expect(chain.map((node) => node.local), <bool>[true, false, true]);
      expect(chain[0].line, 3);
      expect(chain[1].fileUri, isNull);
      expect(chain[2].line, 42);
      expect(vm.requestsTo('ext.flutter.inspector.getParentChain').single['arg'], 'inspector-3');
    });

    test('screenshot decodes base64 and returns null for a null result', () async {
      vm.screenshotResult = base64Encode(<int>[137, 80, 78, 71, 1, 2, 3]);

      expect(await client.screenshot('isolates/1', 'inspector-3'), <int>[137, 80, 78, 71, 1, 2, 3]);

      vm.screenshotResult = null;

      expect(await client.screenshot('isolates/1', 'inspector-3'), isNull);
    });

    test('screenshot asks for 800x800 at a pixel ratio of at most 2', () async {
      vm.screenshotResult = base64Encode(<int>[1]);

      await client.screenshot('isolates/1', 'inspector-3');

      expect(vm.requestsTo('ext.flutter.inspector.screenshot').single, <String, Object?>{
        'isolateId': 'isolates/1',
        'id': 'inspector-3',
        'width': '800',
        'height': '800',
        'maxPixelRatio': '2',
      });
    });

    test('every call passes objectGroup flutter_code_agent_picker', () async {
      vm
        ..selectedSummaryWidget = inspectorNode('BookingCard')
        ..parentChain = <Object?>[inspectorChainEntry(inspectorNode('BookingCard'))]
        ..screenshotResult = base64Encode(<int>[1]);

      await client.selectedWidget('isolates/1');
      await client.parentChain('isolates/1', 'inspector-1');
      await client.disposeGroup('isolates/1');

      for (final method in <String>[
        'ext.flutter.inspector.getSelectedSummaryWidget',
        'ext.flutter.inspector.getParentChain',
        'ext.flutter.inspector.disposeGroup',
      ]) {
        expect(
          vm.requestsTo(method).single['objectGroup'],
          'flutter_code_agent_picker',
          reason: method,
        );
        expect(vm.requestsTo(method).single['isolateId'], 'isolates/1', reason: method);
      }
    });

    test('an extension error is thrown as an RPCError', () async {
      vm.inspectorErrorCode = 113;

      await expectLater(client.selectedWidget('isolates/1'), throwsA(isA<RPCError>()));
      await expectLater(
        client.setSelectMode('isolates/1', enabled: false),
        throwsA(isA<RPCError>()),
      );
    });

    test('close disposes the service once', () async {
      await client.close();
      await client.close();

      expect(vm.disposed, isTrue);
    });

    test('close ends the events', () async {
      final done = Completer<void>();
      client.events.listen((_) {}, onDone: done.complete);

      await client.close();

      await done.future.timeout(const Duration(seconds: 5));
    });

    test('the end of the connection ends the events', () async {
      final done = Completer<void>();
      client.events.listen((_) {}, onDone: done.complete);

      await vm.disconnect();

      await done.future.timeout(const Duration(seconds: 5));
      expect(vm.disposed, isTrue);
    });
  });
}
