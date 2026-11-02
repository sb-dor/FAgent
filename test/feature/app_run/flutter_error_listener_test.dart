import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/data/flutter_error_listener.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

import '../../support/scripted_vm_service.dart';

void main() {
  group('FlutterErrorListener', () {
    late ScriptedVmService vm;
    final listeners = <IFlutterErrorListener>[];

    Future<FlutterErrorListener> attach({
      Duration extensionTimeout = const Duration(seconds: 5),
    }) async {
      final listener = await FlutterErrorListener.attach(
        vm.service,
        extensionTimeout: extensionTimeout,
      );
      listeners.add(listener);
      return listener;
    }

    setUp(() => vm = ScriptedVmService());

    tearDown(() async {
      for (final listener in listeners) {
        await listener.close();
      }
      listeners.clear();
    });

    test('switches structured errors on in the isolate that has the extension', () async {
      vm = ScriptedVmService(
        isolates: <String, List<String>>{
          'isolates/1': <String>['ext.dart.io.getVersion'],
          'isolates/2': <String>[structuredErrorsExtension],
        },
      );

      await attach();

      expect(vm.enabledIn, <String>['isolates/2']);
      expect(
        vm.requests.where((request) => request.method == 'streamListen').map((r) => r.params),
        containsAll(<Object?>[
          <String, Object?>{'streamId': EventStreams.kExtension},
          <String, Object?>{'streamId': EventStreams.kIsolate},
        ]),
      );
    });

    test('a Flutter.Error event of an overflow becomes one RunError', () async {
      final listener = await attach();
      final errors = <RunError>[];
      listener.errors().listen(errors.add);

      vm.emitFlutterError(overflowFlutterError());
      await pumpEventQueue();

      expect(errors, hasLength(1));
      final error = errors.single;
      expect(error.title, 'A RenderFlex overflowed by 42 pixels on the right.');
      expect(error.file, 'file:///p/app/lib/main.dart');
      expect(error.line, 14);
      expect(error.location, 'main.dart:14:18');
      expect(error.message, startsWith('The following assertion was thrown during layout:\n'));
      expect(error.message, contains('A RenderFlex overflowed by 42 pixels on the right.'));
      expect(error.message, isNot(contains('EXCEPTION CAUGHT BY')));
      expect(error.message, isNot(contains('════')));
      expect(error.stack, isNull);
    });

    test('an error after the first since the reload keeps its short text', () async {
      final listener = await attach();
      final errors = <RunError>[];
      listener.errors().listen(errors.add);

      vm.emitFlutterError(overflowFlutterError(errorsSinceReload: 1));
      await pumpEventQueue();

      expect(
        errors.single.message,
        'Another exception was thrown: A RenderFlex overflowed by 42 pixels on the right.',
      );
      expect(errors.single.title, 'A RenderFlex overflowed by 42 pixels on the right.');
    });

    test('takes the place from a creationLocation, the project one first', () async {
      final listener = await attach();
      final errors = <RunError>[];
      listener.errors().listen(errors.add);

      vm.emitFlutterError(<String, Object?>{
        'description': 'Exception caught by widgets library',
        'type': '_FlutterErrorDetailsNode',
        'errorsSinceReload': 0,
        'properties': <Object?>[
          <String, Object?>{
            'description': "type 'Null' is not a subtype of type 'String'",
            'type': 'ErrorSummary',
            'level': 'summary',
          },
          <String, Object?>{
            'description': 'Scaffold',
            'type': 'DiagnosticsProperty<Widget>',
            'creationLocation': <String, Object?>{
              'file': 'file:///sdk/packages/flutter/lib/src/material/app.dart',
              'line': 900,
              'column': 3,
            },
            'children': <Object?>[
              <String, Object?>{
                'description': 'Home',
                'type': 'DiagnosticsProperty<Widget>',
                'createdByLocalProject': true,
                'creationLocation': <String, Object?>{
                  'file': 'file:///p/app/lib/home.dart',
                  'line': 7,
                  'column': 5,
                  'name': 'Home',
                },
              },
            ],
          },
        ],
        'renderedErrorText': "type 'Null' is not a subtype of type 'String'",
      });
      await pumpEventQueue();

      expect(errors.single.file, 'file:///p/app/lib/home.dart');
      expect(errors.single.line, 7);
      expect(errors.single.location, 'home.dart:7:5');
    });

    test('the stack frames of the text go to the stack, not the message', () async {
      final listener = await attach();
      final errors = <RunError>[];
      listener.errors().listen(errors.add);

      vm.emitFlutterError(<String, Object?>{
        'description': 'Exception caught by widgets library',
        'type': '_FlutterErrorDetailsNode',
        'errorsSinceReload': 0,
        'properties': <Object?>[
          <String, Object?>{'description': 'Bad state: boom', 'type': 'ErrorSummary'},
        ],
        'renderedErrorText': '''
══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══════════════════════════════════════════════════════════
The following StateError was thrown building Home(dirty):
Bad state: boom

When the exception was thrown, this was the stack:
#0      Home.build (package:app/home.dart:7:5)
#1      StatelessElement.build (package:flutter/src/widgets/framework.dart:5000:12)
(elided 2 frames from dart:async)
════════════════════════════════════════════════════════════════════════════════════════════════════''',
      });
      await pumpEventQueue();

      final error = errors.single;
      expect(error.title, 'Bad state: boom');
      expect(
        error.stack,
        '#0      Home.build (package:app/home.dart:7:5)\n'
        '#1      StatelessElement.build (package:flutter/src/widgets/framework.dart:5000:12)',
      );
      expect(error.message, isNot(contains('#0')));
      expect(error.message, contains('When the exception was thrown, this was the stack:'));
      expect(error.file, isNull);
    });

    test('an error without a summary is named after its description', () async {
      final listener = await attach();
      final errors = <RunError>[];
      listener.errors().listen(errors.add);

      vm.emitFlutterError(<String, Object?>{
        'description': 'Exception caught by gestures library',
        'type': '_FlutterErrorDetailsNode',
      });
      await pumpEventQueue();

      expect(errors.single.title, 'Exception caught by gestures library');
      expect(errors.single.message, 'Exception caught by gestures library');
    });

    test('other extension events are not errors', () async {
      final listener = await attach();
      final errors = <RunError>[];
      listener.errors().listen(errors.add);

      vm
        ..emitExtension('Flutter.Frame', <String, Object?>{'number': 2})
        ..emitExtension('Flutter.FirstFrame', <String, Object?>{});
      await pumpEventQueue();

      expect(errors, isEmpty);
    });

    test('events before the first listener are kept for it', () async {
      final listener = await attach();
      vm.emitFlutterError(overflowFlutterError());
      await pumpEventQueue();

      final errors = <RunError>[];
      listener.errors().listen(errors.add);
      await pumpEventQueue();

      expect(errors, hasLength(1));
    });

    test('waits for an app that has not registered the extension yet', () async {
      vm = ScriptedVmService(isolates: <String, List<String>>{'isolates/1': <String>[]});
      var attached = false;
      final pending = attach().then((_) => attached = true);
      await pumpEventQueue();
      expect(attached, isFalse);

      vm.addExtension('isolates/1', structuredErrorsExtension);
      await pending;

      expect(vm.enabledIn, <String>['isolates/1']);
    });

    test('an app that never registers the extension times out', () async {
      vm = ScriptedVmService(isolates: <String, List<String>>{'isolates/1': <String>[]});

      await expectLater(
        attach(extensionTimeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('an extension that fails makes attach fail', () async {
      vm.extensionErrorCode = -32000;

      await expectLater(attach(), throwsA(isA<RPCError>()));
    });

    test('switches structured errors on again after a hot restart', () async {
      await attach();

      vm.addExtension('isolates/9', structuredErrorsExtension);
      await pumpEventQueue();

      expect(vm.enabledIn, <String>['isolates/1', 'isolates/9']);
    });

    test('close disposes the connection and ends the errors', () async {
      final listener = await attach();
      var done = false;
      listener.errors().listen(null, onDone: () => done = true);

      await listener.close();
      await listener.close();

      expect(vm.disposed, isTrue);
      expect(done, isTrue);
    });

    test('a connection that the app ends ends the errors', () async {
      final listener = await attach();
      var done = false;
      listener.errors().listen(null, onDone: () => done = true);

      await vm.disconnect();
      await pumpEventQueue();

      expect(done, isTrue);
    });
  });
}
