@Tags(<String>['flutter'])
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_executable.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Runs the real `flutter run --machine` on macOS against a small app it creates in a temp folder
/// and picks a widget of it through the real widget inspector.
///
/// The test cannot tap the screen. It starts the pick, then selects the `Greeting` element through
/// a second VM service connection (`setSelectionById`), which makes the inspector publish the same
/// `navigate` event as a tap does.
///
/// Opt-in: `FLUTTER_RUN_TEST=1 flutter test --tags flutter test/integration/widget_picker_test.dart`.
void main() {
  final enabled = io.Platform.environment['FLUTTER_RUN_TEST'] == '1';

  test(
    'picks the Greeting widget of a running debug app through the real inspector',
    () async {
      final environment = ShellEnvironment(Map<String, String>.of(io.Platform.environment));
      final root = io.Directory.systemTemp.createTempSync('widget_picker_test');
      addTearDown(() => root.deleteSync(recursive: true));
      final flutter = flutterExecutableFor(null, which: environment.which);
      expect(flutter, isNotNull, reason: 'flutter is not on the PATH');

      final project = p.join(root.path, 'picker_probe');
      final created = await io.Process.run(flutter!, <String>[
        'create',
        '--platforms=macos',
        '--project-name',
        'picker_probe',
        project,
      ], environment: environment.variables);
      expect(created.exitCode, 0, reason: '${created.stdout}\n${created.stderr}');
      io.File(p.join(project, 'lib', 'main.dart')).writeAsStringSync(_app);

      final runs = AppRunRepositoryImpl(
        projectPath: (_) async => project,
        flutter: (_) => flutter,
        environment: environment.variables,
      );
      addTearDown(runs.dispose);
      final states = <RunState>[];
      final logs = <LogEntry>[];
      final subscriptions = <StreamSubscription<Object?>>[
        runs.watchRun(1).listen(states.add),
        runs.logs(1).listen(logs.add),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });
      String output() => logs.map((entry) => entry.text).join('\n');

      await runs.start(
        1,
        device: const Device(
          id: 'macos',
          name: 'macOS',
          platform: DevicePlatform.macos,
          kind: DeviceKind.running,
        ),
        mode: BuildMode.debug,
        target: 'lib/main.dart',
      );
      // Registered after the repository's dispose, so it runs first, even when the test fails.
      addTearDown(() => runs.stop(1));
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (states.lastOrNull is! RunRunning) {
        if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for the app.\n${output()}');
        if (states.lastOrNull is RunFailed) fail('The run failed: ${states.last}\n${output()}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final uri = (states.last as RunRunning).vmServiceUri;
      expect(uri, isNotNull);

      final picker = WidgetPickerRepositoryImpl(runs: runs, projectRoot: (_) async => project);
      addTearDown(picker.dispose);
      final vm = await vmServiceConnectUri(uri.toString());
      addTearDown(vm.dispose);
      final isolateId = await _inspectorIsolate(vm);
      Future<bool> selectModeOn() async {
        final response = await vm.callServiceExtension(
          'ext.flutter.inspector.show',
          isolateId: isolateId,
        );
        return response.json?['enabled'] == 'true';
      }

      expect(await selectModeOn(), isFalse);
      final pick = picker.pick(1);
      // The pick turns the select mode on and waits for the tap.
      final modeDeadline = DateTime.now().add(const Duration(seconds: 20));
      while (!await selectModeOn()) {
        if (DateTime.now().isAfter(modeDeadline)) fail('The pick never turned the select mode on');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await _select(vm, isolateId, 'Greeting');
      final result = await pick.timeout(const Duration(seconds: 30));

      expect(result, isA<PickPicked>(), reason: '$result\n${output()}');
      final widget = (result as PickPicked).widget;
      expect(widget.name, 'Greeting');
      expect(widget.file, 'lib/main.dart');
      expect(widget.line, greaterThan(0));
      expect(widget.column, greaterThan(0));
      expect(widget.id, isNotNull);
      final chain = widget.ancestors.map((ancestor) => ancestor.name).toList();
      expect(chain, containsAll(<String>['Scaffold', 'MaterialApp']), reason: '$chain');
      expect(chain, isNot(contains('Greeting')));
      expect(chain.length, lessThanOrEqualTo(kPickedAncestorLimit));
      expect(widget.screenshot, isNotNull, reason: 'no screenshot of the widget');
      final png = io.File(p.join(project, widget.screenshot!));
      expect(png.existsSync(), isTrue);
      final bytes = png.readAsBytesSync();
      expect(bytes, isNotEmpty);
      expect(bytes.take(4), <int>[0x89, 0x50, 0x4E, 0x47], reason: 'not a PNG');
      expect(await selectModeOn(), isFalse, reason: 'the select mode stayed on');
      // ignore: avoid_print
      print(
        'picked $widget, chain $chain, screenshot ${widget.screenshot} (${bytes.length} bytes)',
      );

      // A click on a link of the chain switches the card to that widget.
      final scaffold = widget.ancestors.firstWhere((ancestor) => ancestor.name == 'Scaffold');
      final switched = await picker.select(1, scaffold.id);
      expect(switched, isA<PickPicked>(), reason: '$switched');
      expect((switched as PickPicked).widget.name, 'Scaffold');
      expect(switched.widget.file, 'lib/main.dart');
      expect(await selectModeOn(), isFalse);

      await runs.stop(1);
      final stopDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (states.last != const RunStopped() && DateTime.now().isBefore(stopDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(states.last, const RunStopped());
      expect(await picker.select(1, scaffold.id), isA<PickGone>());
    },
    skip: enabled ? false : 'Runs the real flutter on macOS; set FLUTTER_RUN_TEST=1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// An app with one widget of its own, `Greeting`, inside a `Scaffold` in a `MaterialApp`.
const String _app = '''
import 'package:flutter/material.dart';

void main() => runApp(
  const MaterialApp(
    home: Scaffold(body: Center(child: Greeting())),
  ),
);

class Greeting extends StatelessWidget {
  const Greeting({super.key});

  @override
  Widget build(BuildContext context) => const Text('Hello');
}
''';

/// The id of the isolate that has the widget inspector.
Future<String> _inspectorIsolate(VmService vm) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    for (final ref in (await vm.getVM()).isolates ?? const <IsolateRef>[]) {
      final isolate = await vm.getIsolate(ref.id!);
      if (isolate.extensionRPCs?.contains('ext.flutter.inspector.show') ?? false) return ref.id!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('No isolate with the widget inspector');
}

/// Selects the element of the widget called [name], as a tap would.
Future<void> _select(VmService vm, String isolateId, String name) async {
  const group = 'widget_picker_test';
  final response = await vm.callServiceExtension(
    'ext.flutter.inspector.getRootWidgetSummaryTree',
    isolateId: isolateId,
    args: <String, Object?>{'objectGroup': group},
  );
  String? find(Object? node) {
    if (node is! Map) return null;
    if (node['description'] == name) return node['valueId'] as String?;
    for (final child in (node['children'] as List<Object?>?) ?? const <Object?>[]) {
      final id = find(child);
      if (id != null) return id;
    }
    return null;
  }

  final id = find(response.json?['result']);
  expect(id, isNotNull, reason: 'no $name in the summary tree: ${response.json}');
  await vm.callServiceExtension(
    'ext.flutter.inspector.setSelectionById',
    isolateId: isolateId,
    args: <String, Object?>{'arg': id, 'objectGroup': group},
  );
}
