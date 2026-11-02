import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_inspector_client.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/scripted_app_run_repository.dart';
import '../../support/scripted_vm_service.dart';

const Device _macos = Device(
  id: 'macos',
  name: 'macOS',
  platform: DevicePlatform.macos,
  kind: DeviceKind.running,
);

const List<int> _png = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3];

const Duration _endTimeout = Duration(milliseconds: 300);
const Duration _runEndTimeout = Duration(milliseconds: 200);

const String _show = inspectorShowExtension;
const String _selected = 'ext.flutter.inspector.getSelectedSummaryWidget';
const String _chain = 'ext.flutter.inspector.getParentChain';
const String _screenshot = 'ext.flutter.inspector.screenshot';
const String _disposeGroup = 'ext.flutter.inspector.disposeGroup';

RunRunning _running(Uri? vmServiceUri, {BuildMode mode = BuildMode.debug}) => RunRunning(
  device: _macos,
  startedAt: DateTime(2026, 11, 2),
  mode: mode,
  vmServiceUri: vmServiceUri,
);

void main() {
  late io.Directory temp;
  late Map<int, String> roots;
  late ScriptedAppRunRepository runs;
  late WidgetPickerRepositoryImpl picker;

  /// The VM services the picker connected to, in order, with the address it asked for.
  late List<({Uri uri, ScriptedVmService vm})> connections;

  /// Builds the VM service of the next connection; each test may replace it.
  late ScriptedVmService Function(Uri uri) nextVm;

  final uri1 = Uri.parse('ws://127.0.0.1:1111/a=/ws');
  final uri2 = Uri.parse('ws://127.0.0.1:2222/b=/ws');

  String fileIn(int projectId, String relative) =>
      p.toUri(p.join(roots[projectId]!, relative)).toString();

  /// A VM service of a debug app of project 1: `BookingCard` is selected; its chain from the root
  /// mixes project widgets and Flutter's own.
  ScriptedVmService bookingApp({int projectId = 1}) {
    String file(String name) => fileIn(projectId, 'lib/$name.dart');
    return ScriptedVmService(isolates: <String, List<String>>{'isolates/1': inspectorExtensions})
      ..selectedSummaryWidget = inspectorNode(
        'BookingCard',
        valueId: 'inspector-card',
        file: file('booking_card'),
        line: 42,
        column: 7,
      )
      ..parentChain = <Object?>[
        inspectorChainEntry(inspectorNode('MyApp', valueId: 'inspector-app', file: file('main'))),
        inspectorChainEntry(
          inspectorNode('MaterialApp', valueId: 'inspector-material', file: null, local: false),
        ),
        inspectorChainEntry(
          inspectorNode(
            'BookingScreen',
            valueId: 'inspector-screen',
            file: file('booking_screen'),
            line: 9,
            column: 12,
          ),
        ),
        inspectorChainEntry(
          inspectorNode('ListView', valueId: 'inspector-list-view', local: false),
        ),
        inspectorChainEntry(
          inspectorNode(
            'BookingList',
            valueId: 'inspector-list',
            file: file('booking_list'),
            line: 20,
            column: 5,
          ),
        ),
        inspectorChainEntry(
          inspectorNode('Padding', valueId: 'inspector-padding', file: null, local: false),
        ),
        inspectorChainEntry(
          inspectorNode(
            'BookingCard',
            valueId: 'inspector-card',
            file: file('booking_card'),
            line: 42,
            column: 7,
          ),
        ),
      ]
      ..screenshotResult = base64Encode(_png);
  }

  /// A picker over [runs] and the VM services of [nextVm], with short waits for an app that answers
  /// nothing ([_endTimeout]) and for a run to end after its connection dropped ([_runEndTimeout]).
  WidgetPickerRepositoryImpl newPicker({Future<String?> Function(int projectId)? projectRoot}) =>
      WidgetPickerRepositoryImpl(
        runs: runs,
        projectRoot: projectRoot ?? (projectId) async => roots[projectId],
        connect: (uri) async {
          final vm = nextVm(uri);
          connections.add((uri: uri, vm: vm));
          return WidgetInspectorClient.attach(vm.service);
        },
        endTimeout: _endTimeout,
        runEndTimeout: _runEndTimeout,
      );

  setUp(() {
    temp = io.Directory.systemTemp.createTempSync('widget_picker_test_');
    roots = <int, String>{
      for (final (id, name) in <(int, String)>[(1, 'one'), (2, 'two')])
        id: (io.Directory(p.join(temp.path, name))..createSync()).path,
    };
    runs = ScriptedAppRunRepository(step: const Duration(milliseconds: 1))
      ..setRunState(1, _running(uri1));
    connections = <({Uri uri, ScriptedVmService vm})>[];
    nextVm = (_) => bookingApp();
    picker = newPicker();
  });

  tearDown(() async {
    await picker.dispose();
    await runs.dispose();
    temp.deleteSync(recursive: true);
  });

  ScriptedVmService vm([int index = 0]) => connections[index].vm;

  /// The `enabled` values of the `show` calls to [service], in order.
  List<Object?> shows(ScriptedVmService service) => <Object?>[
    for (final params in service.requestsTo(_show)) params['enabled'],
  ];

  /// Waits until the picker turned the select mode on [times] times in [service] and listens for
  /// the tap.
  Future<void> untilWaiting({int index = 0, int times = 1}) async {
    for (var i = 0; i < 50; i++) {
      if (connections.length > index &&
          shows(vm(index)).where((e) => e == 'true').length >= times) {
        break;
      }
      await pumpEventQueue();
    }
    expect(shows(vm(index)).where((e) => e == 'true'), hasLength(times));
    await pumpEventQueue();
  }

  /// Starts a pick of [projectId] and taps the selected widget once the app waits for it.
  Future<PickResult> pickAndTap({int projectId = 1, int index = 0, int times = 1}) async {
    final result = picker.pick(projectId);
    await untilWaiting(index: index, times: times);
    vm(index).emitNavigate();
    return result;
  }

  PickedWidget picked(PickResult result) => (result as PickPicked).widget;

  group('WidgetPickerRepositoryImpl', () {
    test('pick returns the widget, project-relative file, column, ancestors nearest first and at '
        'most 8, local only', () async {
      final widget = picked(await pickAndTap());

      expect(widget.name, 'BookingCard');
      expect(widget.file, 'lib/booking_card.dart');
      expect(widget.line, 42);
      expect(widget.column, 7);
      expect(widget.id, 'inspector-card');
      expect(widget.ancestors, const <PickedAncestor>[
        PickedAncestor(
          name: 'BookingList',
          file: 'lib/booking_list.dart',
          line: 20,
          column: 5,
          id: 'inspector-list',
        ),
        PickedAncestor(
          name: 'BookingScreen',
          file: 'lib/booking_screen.dart',
          line: 9,
          column: 12,
          id: 'inspector-screen',
        ),
        PickedAncestor(
          name: 'MyApp',
          file: 'lib/main.dart',
          line: 14,
          column: 18,
          id: 'inspector-app',
        ),
      ]);
      expect(vm().requestsTo(_chain).single['arg'], 'inspector-card');
    });

    test(
      'at most 8 ancestors, the nearest ones; a file outside the project stays absolute',
      () async {
        nextVm = (_) => bookingApp()
          ..parentChain = <Object?>[
            inspectorChainEntry(
              inspectorNode('Outside', valueId: 'inspector-out', file: 'file:///elsewhere/x.dart'),
            ),
            for (var i = 0; i < 10; i++)
              inspectorChainEntry(
                inspectorNode('Level$i', valueId: 'inspector-$i', file: fileIn(1, 'lib/l$i.dart')),
              ),
            inspectorChainEntry(
              inspectorNode(
                'BookingCard',
                valueId: 'inspector-card',
                file: fileIn(1, 'lib/c.dart'),
              ),
            ),
          ];

        final ancestors = picked(await pickAndTap()).ancestors;

        expect(ancestors.map((a) => a.name), <String>[for (var i = 9; i >= 2; i--) 'Level$i']);

        vm().parentChain = <Object?>[
          inspectorChainEntry(
            inspectorNode('Outside', valueId: 'inspector-out', file: 'file:///elsewhere/x.dart'),
          ),
          inspectorChainEntry(
            inspectorNode('BookingCard', valueId: 'inspector-card', file: fileIn(1, 'lib/c.dart')),
          ),
        ];
        final outside = picked(await pickAndTap(times: 2)).ancestors.single;

        expect(outside.file, '/elsewhere/x.dart');
      },
    );

    test('screenshot saved as widget-<Name>.png under the screenshots folder', () async {
      final widget = picked(await pickAndTap());

      expect(widget.screenshot, '$kScreenshotsFolder/widget-BookingCard.png');
      expect(io.File(p.join(roots[1]!, widget.screenshot)).readAsBytesSync(), _png);
      expect(vm().requestsTo(_screenshot).single, <String, Object?>{
        'isolateId': 'isolates/1',
        'id': 'inspector-card',
        'width': '800',
        'height': '800',
        'maxPixelRatio': '2',
      });
    });

    test('a non-file-safe name is sanitized and numbered on collision', () async {
      nextVm = (_) => bookingApp()
        ..selectedSummaryWidget = inspectorNode(
          'Foo<Bar>',
          valueId: 'inspector-foo',
          file: fileIn(1, 'lib/foo.dart'),
        );

      final first = picked(await pickAndTap());
      final second = picked(await pickAndTap(times: 2));
      vm().selectedSummaryWidget = inspectorNode(
        '_Private',
        valueId: 'inspector-private',
        file: fileIn(1, 'lib/private.dart'),
      );
      final third = picked(await pickAndTap(times: 3));

      expect(first.name, 'Foo<Bar>');
      expect(first.screenshot, '$kScreenshotsFolder/widget-FooBar.png');
      expect(second.screenshot, '$kScreenshotsFolder/widget-FooBar-2.png');
      expect(third.screenshot, '$kScreenshotsFolder/widget-_Private.png');
      for (final shot in <String?>[first.screenshot, second.screenshot, third.screenshot]) {
        expect(io.File(p.join(roots[1]!, shot)).existsSync(), isTrue);
      }
    });

    test('widget PNGs count toward the screenshot limit', () async {
      final folder = io.Directory(p.join(roots[1]!, kScreenshotsFolder))
        ..createSync(recursive: true);
      for (var i = 0; i < kScreenshotLimit; i++) {
        io.File(p.join(folder.path, 'screenshot-20261031-0905${'$i'.padLeft(2, '0')}.png'))
          ..writeAsBytesSync(_png)
          ..setLastModifiedSync(DateTime(2026, 10, 31, 9, 5, i));
      }

      final widget = picked(await pickAndTap());

      final names = folder.listSync().map((entity) => p.basename(entity.path)).toList();
      expect(names, hasLength(kScreenshotLimit));
      expect(names, contains(p.basename(widget.screenshot!)));
      expect(names, isNot(contains('screenshot-20261031-090500.png')));
    });

    test('select mode off after success, cancel and error', () async {
      await pickAndTap();
      expect(shows(vm()), <Object?>['true', 'false']);

      final cancelled = picker.pick(1);
      await untilWaiting(times: 2);
      await picker.cancel(1);
      expect(await cancelled, isA<PickCancelled>());
      expect(shows(vm()), <Object?>['true', 'false', 'true', 'false']);

      final failed = picker.pick(1);
      await untilWaiting(times: 3);
      vm()
        ..inspectorErrorCode = -32000
        ..emitNavigate();
      expect(
        await failed,
        const PickFailed(PickFailure.inspectorError, detail: 'Extension failed'),
      );
      expect(shows(vm()), <Object?>['true', 'false', 'true', 'false', 'true', 'false']);
    });

    test('cancel ends the pick as PickCancelled', () async {
      final result = picker.pick(1);
      await untilWaiting();

      await picker.cancel(1);

      expect(await result, isA<PickCancelled>());
      expect(vm().requestsTo(_selected), isEmpty);
    });

    test('cancel without a pick does nothing', () async {
      await picker.cancel(1);
      await picker.cancel(3);

      expect(connections, isEmpty);
    });

    test('leaving select mode in the app cancels', () async {
      final result = picker.pick(1);
      await untilWaiting();

      vm().emitSelectModeChanged(false);

      expect(await result, isA<PickCancelled>());
      expect(vm().requestsTo(_selected), isEmpty);
    });

    test('the echo of its own show calls is no cancel, of this pick or the next', () async {
      // Every show call echoes its state (ScriptedVmService does it as the framework does).
      final first = picker.pick(1);
      await untilWaiting();
      await pumpEventQueue();
      vm().emitNavigate();
      expect(await first, isA<PickPicked>());
      expect(shows(vm()), <Object?>['true', 'false']);

      // The echo of the first pick's show(false) has come by now; the next pick waits all the same.
      final second = picker.pick(1);
      var done = false;
      unawaited(second.then((_) => done = true));
      await untilWaiting(times: 2);
      await pumpEventQueue();
      expect(done, isFalse);

      vm().emitNavigate();
      expect(await second, isA<PickPicked>());
    });

    test('a tap in another isolate does not end the pick', () async {
      final result = picker.pick(1);
      var done = false;
      unawaited(result.then((_) => done = true));
      await untilWaiting();

      vm().emitNavigate(isolateId: 'isolates/9');
      await pumpEventQueue();
      expect(done, isFalse);

      vm().emitNavigate();
      expect(await result, isA<PickPicked>());
    });

    test('hot restart (isolate exit) cancels and the next pick uses the new isolate', () async {
      final result = picker.pick(1);
      await untilWaiting();

      vm()
        ..isolates['isolates/2'] = inspectorExtensions
        ..exitIsolate('isolates/1');

      expect(await result, isA<PickCancelled>());
      final next = picker.pick(1);
      await untilWaiting(times: 2);
      vm().emitNavigate(isolateId: 'isolates/2');

      expect(await next, isA<PickPicked>());
      expect(connections, hasLength(1));
      final calls = vm().requests.where((r) => r.method.startsWith('ext.flutter.inspector.'));
      expect(calls.last.params['isolateId'], 'isolates/2');
      expect(
        vm().requestsTo(_show).where((params) => params['enabled'] == 'true').last['isolateId'],
        'isolates/2',
      );
    });

    test('run stop cancels and closes the client', () async {
      final result = picker.pick(1);
      await untilWaiting();

      runs.setRunState(1, const RunStopped());

      expect(await result, isA<PickCancelled>());
      await pumpEventQueue();
      expect(shows(vm()).last, 'false');
      expect(vm().disposed, isTrue);
    });

    test('a new VM service address closes the client and the next pick connects to it', () async {
      await pickAndTap();

      runs.setRunState(1, _running(uri2));
      await pumpEventQueue();
      expect(vm().disposed, isTrue);

      await pickAndTap(index: 1);
      expect(connections.map((c) => c.uri), <Uri>[uri1, uri2]);
    });

    test('no inspector isolate fails with the spec line', () async {
      nextVm = (_) => ScriptedVmService(
        isolates: <String, List<String>>{
          'isolates/1': <String>[structuredErrorsExtension],
        },
      );

      final result = await picker.pick(1);

      expect(result, const PickFailed(PickFailure.inspectorUnavailable));
    });

    test(
      'a run that is not debug, not running or without a VM service fails with the spec line',
      () async {
        for (final state in <RunState>[
          const RunIdle(),
          _running(uri1, mode: BuildMode.profile),
          _running(null),
        ]) {
          runs.setRunState(1, state);

          expect(await picker.pick(1), const PickFailed(PickFailure.notDebug));
        }
        expect(connections, isEmpty);
      },
    );

    test('a dropped VM service connection, the run still running, fails as connectionLost after '
        'the wait and the next pick connects again', () async {
      final result = picker.pick(1);
      await untilWaiting();
      final stopwatch = Stopwatch()..start();

      await vm().disconnect();

      expect(await result, const PickFailed(PickFailure.connectionLost));
      expect(stopwatch.elapsed, greaterThanOrEqualTo(_runEndTimeout));
      // No show(false) to a connection that is gone.
      expect(shows(vm()), <Object?>['true']);
      final next = await pickAndTap(index: 1);
      expect(next, isA<PickPicked>());
      expect(connections, hasLength(2));
    });

    test('a stop that closes the connection before the run reports it cancels', () async {
      final result = picker.pick(1);
      await untilWaiting();

      await vm().disconnect();
      await pumpEventQueue();
      runs.setRunState(1, const RunStopped());

      expect(await result, isA<PickCancelled>());
      expect(shows(vm()), <Object?>['true']);
    });

    for (final (what, method) in <(String, String)>[
      ('the screenshot', _screenshot),
      ('show(true)', _show),
    ]) {
      test('dispose while the app never answers $what ends within the bound, closes and '
          'cancels', () async {
        nextVm = (_) => bookingApp()..unanswered.add(method);
        final result = picker.pick(1);
        await untilWaiting();
        if (method == _screenshot) {
          vm().emitNavigate();
          for (var i = 0; i < 20 && vm().requestsTo(_screenshot).isEmpty; i++) {
            await pumpEventQueue();
          }
          expect(vm().requestsTo(_screenshot), hasLength(1));
        }
        final stopwatch = Stopwatch()..start();

        await picker.dispose().timeout(_endTimeout * 3);

        expect(stopwatch.elapsed, lessThan(_endTimeout * 3));
        expect(vm().disposed, isTrue);
        expect(await result.timeout(_endTimeout), isA<PickCancelled>());
      });
    }

    test(
      'cancel while the app never answers ends within the bound and closes the connection',
      () async {
        nextVm = (_) => bookingApp()..unanswered.add(_screenshot);
        final result = picker.pick(1);
        await untilWaiting();
        vm().emitNavigate();
        for (var i = 0; i < 20 && vm().requestsTo(_screenshot).isEmpty; i++) {
          await pumpEventQueue();
        }

        await picker.cancel(1).timeout(_endTimeout * 4);

        expect(vm().disposed, isTrue);
        expect(await result.timeout(_endTimeout), isA<PickCancelled>());
        // The next pick connects again.
        vm().unanswered.clear();
        nextVm = (_) => bookingApp();
        expect(await pickAndTap(index: 1), isA<PickPicked>());
      },
    );

    test('a screenshot that fails keeps the widget without a screenshot', () async {
      nextVm = (_) => bookingApp()..failing.add(_screenshot);

      final widget = picked(await pickAndTap());

      expect(widget.name, 'BookingCard');
      expect(widget.screenshot, isNull);
    });

    test(
      'an error of the picker itself fails as inspectorError, not as a lost connection',
      () async {
        await picker.dispose();
        picker = newPicker(projectRoot: (_) async => throw StateError('the database is closed'));

        final result = await pickAndTap();

        expect(
          result,
          const PickFailed(PickFailure.inspectorError, detail: 'Bad state: the database is closed'),
        );
        expect(shows(vm()).last, 'false');
      },
    );

    test(
      'a connection that cannot be opened fails with "Lost the connection to the app"',
      () async {
        nextVm = (_) => throw const io.SocketException('refused');

        expect(await picker.pick(1), const PickFailed(PickFailure.connectionLost));
      },
    );

    test('tap outside project widgets gives PickNoProjectWidget', () async {
      nextVm = (_) => bookingApp()..selectedSummaryWidget = null;
      expect(await pickAndTap(), isA<PickNoProjectWidget>());

      vm().selectedSummaryWidget = inspectorNode('Padding', valueId: 'inspector-p', local: false);
      expect(await pickAndTap(times: 2), isA<PickNoProjectWidget>());
      expect(shows(vm()).last, 'false');
      expect(vm().requestsTo(_screenshot), isEmpty);
    });

    test('null screenshot keeps the widget without a screenshot', () async {
      nextVm = (_) => bookingApp()..screenshotResult = null;

      final widget = picked(await pickAndTap());

      expect(widget.name, 'BookingCard');
      expect(widget.screenshot, isNull);
      expect(io.Directory(p.join(roots[1]!, kScreenshotsFolder)).existsSync(), isFalse);
    });

    test('select by a chain id returns that widget', () async {
      await pickAndTap();
      final file = fileIn(1, 'lib/booking_list.dart');
      vm().parentChain = <Object?>[
        inspectorChainEntry(
          inspectorNode('MyApp', valueId: 'inspector-app', file: fileIn(1, 'lib/main.dart')),
        ),
        inspectorChainEntry(
          inspectorNode('BookingList', valueId: 'inspector-list', file: file, line: 20, column: 5),
        ),
      ];

      final widget = picked(await picker.select(1, 'inspector-list'));

      expect(widget.name, 'BookingList');
      expect(widget.file, 'lib/booking_list.dart');
      expect(widget.line, 20);
      expect(widget.column, 5);
      expect(widget.id, 'inspector-list');
      expect(widget.ancestors.map((a) => a.name), <String>['MyApp']);
      expect(widget.screenshot, '$kScreenshotsFolder/widget-BookingList.png');
      expect(vm().requestsTo(_chain).last['arg'], 'inspector-list');
      expect(vm().requestsTo(_screenshot).last['id'], 'inspector-list');
      // No new pick: the select mode stays off, the group is kept.
      expect(shows(vm()), <Object?>['true', 'false']);
      expect(vm().requestsTo(_disposeGroup), hasLength(1));

      // An id of the new chain can be selected in turn.
      expect(await picker.select(1, 'inspector-app'), isA<PickPicked>());
    });

    test('select after the group was released gives PickGone', () async {
      await pickAndTap();
      final next = picker.pick(1);
      await untilWaiting(times: 2);
      await picker.cancel(1);
      await next;
      final asked = vm().requestsTo(_chain).length;

      expect(await picker.select(1, 'inspector-list'), isA<PickGone>());
      expect(vm().requestsTo(_chain), hasLength(asked));
    });

    test('select of an id the app no longer knows, an unknown id, after a hot restart or a stop '
        'gives PickGone', () async {
      await pickAndTap();
      vm().inspectorErrorCode = -32000;
      expect(await picker.select(1, 'inspector-list'), isA<PickGone>());
      vm().inspectorErrorCode = null;

      expect(await picker.select(1, 'inspector-nope'), isA<PickGone>());

      vm().exitIsolate('isolates/1');
      await pumpEventQueue();
      expect(await picker.select(1, 'inspector-list'), isA<PickGone>());

      expect(await picker.select(2, 'inspector-list'), isA<PickGone>());
    });

    test('select after the run stopped gives PickGone', () async {
      await pickAndTap();
      runs.setRunState(1, const RunStopped());
      await pumpEventQueue();

      expect(await picker.select(1, 'inspector-list'), isA<PickGone>());
    });

    test('two projects use separate clients', () async {
      runs.setRunState(2, _running(uri2));
      nextVm = (uri) => bookingApp(projectId: uri == uri2 ? 2 : 1);
      final first = picker.pick(1);
      var firstDone = false;
      unawaited(first.then((_) => firstDone = true));
      await untilWaiting();

      final second = picker.pick(2);
      await untilWaiting(index: 1);
      vm(1).emitNavigate();
      final widget = picked(await second);

      expect(connections.map((c) => c.uri), <Uri>[uri1, uri2]);
      expect(widget.file, 'lib/booking_card.dart');
      expect(io.File(p.join(roots[2]!, widget.screenshot)).existsSync(), isTrue);
      await pumpEventQueue();
      expect(firstDone, isFalse);
      expect(shows(vm()), <Object?>['true']);

      runs.setRunState(2, const RunStopped());
      await pumpEventQueue();
      expect(vm(1).disposed, isTrue);
      expect(vm().disposed, isFalse);
      expect(firstDone, isFalse);

      vm().emitNavigate();
      expect(await first, isA<PickPicked>());
    });

    test('dispose during a pick turns select mode off and closes', () async {
      final result = picker.pick(1);
      await untilWaiting();

      await picker.dispose();

      expect(await result, isA<PickCancelled>());
      expect(shows(vm()), <Object?>['true', 'false']);
      expect(vm().disposed, isTrue);
      expect(await picker.pick(1), isA<PickCancelled>());
    });

    test('the group is disposed before each pick', () async {
      await pickAndTap();
      await pickAndTap(times: 2);

      final calls = <String>[
        for (final request in vm().requests)
          if (request.method == _show)
            'show:${request.params['enabled']}'
          else if (request.method == _disposeGroup)
            'dispose',
      ];
      expect(calls, <String>[
        'dispose',
        'show:true',
        'show:false',
        'dispose',
        'show:true',
        'show:false',
      ]);
      expect(vm().requestsTo(_disposeGroup).first['objectGroup'], kInspectorObjectGroup);
    });

    test('a second pick of the same project ends the first one', () async {
      final first = picker.pick(1);
      await untilWaiting();

      final second = picker.pick(1);
      expect(await first, isA<PickCancelled>());
      await untilWaiting(times: 2);
      vm().emitNavigate();

      expect(await second, isA<PickPicked>());
      expect(shows(vm()), <Object?>['true', 'false', 'true', 'false']);
    });
  });
}
