import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_config_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/launch_config_reader.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/build_mode.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/launch_config.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_tab.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_run_config_repository.dart';
import '../../support/scripted_app_run_repository.dart';
import '../../support/test_app.dart';

const LaunchConfig _dev = LaunchConfig(name: 'Run DEV', flavor: 'dev');
const LaunchConfig _web = LaunchConfig(name: 'Run Web', deviceId: 'web-server');
const LaunchConfig _release = LaunchConfig(name: 'Run Release', mode: BuildMode.release);
const LaunchConfig _broken = LaunchConfig(
  name: 'Broken',
  unsupported: LaunchUnsupportedVariable(r'${env:HOME}'),
);
const LaunchConfig _elsewhere = LaunchConfig(
  name: 'Elsewhere',
  unsupported: LaunchCwdOutsideProject('/other'),
);
const LaunchConfig _pre = LaunchConfig(name: 'With task', hasPreLaunchTask: true);

const LaunchConfigsRead _all = LaunchConfigsRead(<LaunchConfig>[
  _dev,
  _web,
  _release,
  _broken,
  _elsewhere,
  _pre,
]);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('RunSplitButton', () {
    late MemoryRunConfigRepository configs;
    late Dependencies dependencies;
    late DevicesController devices;
    late RunController run;
    late RunActionsController actions;
    late RunConfigController runConfig;
    late List<(String, int?)> openedFiles;
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('run_split_button_test');
      configs = MemoryRunConfigRepository(launch: <int, LaunchConfigs>{1: _all});
      dependencies = testDependencies(runConfigRepository: configs);
      devices = DevicesController(repository: dependencies.devicesRepository);
      run = RunController(
        repository: dependencies.appRunRepository,
        configRepository: dependencies.runConfigRepository,
      );
      actions = RunActionsController(
        runRepository: dependencies.appRunRepository,
        pickerRepository: dependencies.widgetPickerRepository,
      );
      runConfig = RunConfigController(repository: dependencies.runConfigRepository);
      openedFiles = <(String, int?)>[];
    });

    tearDown(() {
      devices.dispose();
      run.dispose();
      actions.dispose();
      runConfig.dispose();
      root.deleteSync(recursive: true);
    });

    Future<void> pumpTab(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      bool chooseDevice = true,
    }) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      run.watch(1);
      devices.watch();
      if (chooseDevice) run.choose(deviceId: 'ios-sim-16-pro');
      await tester.pumpWidget(
        testApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 420,
              child: RunTab(
                projectId: 1,
                projectRoot: root.path,
                isPreview: true,
                devices: devices,
                run: run,
                actions: actions,
                runConfig: runConfig,
                onSendError: (_) {},
                onAddWidget: (_) {},
                onOpenFile: (path, line) => openedFiles.add((path, line)),
                onOpenFlutterSettings: () {},
              ),
            ),
          ),
          dependencies: dependencies,
          locale: locale,
          withSettings: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }

    Future<void> openMenu(WidgetTester tester, [String tooltip = 'Run configuration']) async {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
    }

    ScriptedAppRunRepository scripted() =>
        dependencies.appRunRepository as ScriptedAppRunRepository;

    testWidgets('the label shows the selected configuration, Default shows just Run', (
      tester,
    ) async {
      await pumpTab(tester);
      expect(find.text('Run'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);

      run.chooseConfig('Run DEV');
      await tester.pump();

      expect(find.text('Run · Run DEV'), findsOneWidget);
      expect(find.byTooltip('Run · Run DEV'), findsOneWidget, reason: 'the full name');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a stored selection shows in the label once the file is read', (tester) async {
      configs = MemoryRunConfigRepository(
        launch: <int, LaunchConfigs>{1: _all},
        selected: <int, String>{1: 'Run DEV'},
      );
      dependencies = testDependencies(runConfigRepository: configs);
      run.dispose();
      run = RunController(
        repository: dependencies.appRunRepository,
        configRepository: dependencies.runConfigRepository,
      );
      await pumpTab(tester);
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('Run · Run DEV'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a long name is ellipsized and keeps the full name in the tooltip', (tester) async {
      const name = 'Run PRODUCTION Web Server (Release, obfuscated, with the long name)';
      configs.launch[1] = const LaunchConfigsRead(<LaunchConfig>[LaunchConfig(name: name)]);
      await pumpTab(tester);
      run.chooseConfig(name);
      await tester.pump();

      expect(find.byTooltip('Run · $name'), findsOneWidget);
      final label = tester.widget<Text>(find.text('Run · $name'));
      expect(label.overflow, TextOverflow.ellipsis);
      expect(label.maxLines, 1);
      expect(tester.takeException(), isNull);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('tap runs; the arrow opens the menu with Default and the configurations', (
      tester,
    ) async {
      await pumpTab(tester);

      await tester.tap(find.byTooltip('Run'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(scripted().starts, hasLength(1), reason: 'the main part runs');
      expect(find.text('Default'), findsNothing, reason: 'and does not open the menu');

      await tester.tap(find.byTooltip('Stop the app'));
      await tester.pump(const Duration(milliseconds: 20));
      await openMenu(tester);

      expect(find.text('Default'), findsOneWidget);
      for (final name in <String>[
        'Run DEV',
        'Run Web',
        'Run Release',
        'Broken',
        'Elsewhere',
        'With task',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('Open launch.json'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('opening the menu reads launch.json again', (tester) async {
      await pumpTab(tester);
      final reads = configs.launchReads.length;
      configs.launch[1] = const LaunchConfigsRead(<LaunchConfig>[LaunchConfig(name: 'Fresh')]);

      await openMenu(tester);

      expect(configs.launchReads.length, greaterThan(reads));
      expect(find.text('Fresh'), findsOneWidget);
      expect(find.text('Run DEV'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('choosing a configuration calls chooseConfig; Default goes back', (tester) async {
      await pumpTab(tester);

      await openMenu(tester);
      await tester.tap(find.text('Run Web'));
      await tester.pumpAndSettle();
      expect(run.state.selectedConfig, 'Run Web');
      expect(configs.savedSelections.last, (1, 'Run Web'));
      expect(run.state.selectedDeviceId, 'web-server', reason: 'the configuration\'s device');
      expect(find.text('Run · Run Web'), findsOneWidget);

      await openMenu(tester);
      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();
      expect(run.state.selectedConfig, isNull);
      expect(configs.savedSelections.last, (1, null));
      expect(find.text('Run'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the selected configuration is marked in the menu', (tester) async {
      await pumpTab(tester);
      run.chooseConfig('Run DEV');
      await tester.pump();

      await openMenu(tester);
      expect(find.byIcon(Icons.check), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('an unsupported configuration is disabled with its reason', (tester) async {
      await pumpTab(tester);
      await openMenu(tester);

      expect(find.text(r'Unsupported: ${env:HOME}'), findsOneWidget);
      expect(find.text('Unsupported: cwd /other is outside the project'), findsOneWidget);
      await tester.tap(find.text('Broken'));
      await tester.pumpAndSettle();

      expect(run.state.selectedConfig, isNull);
      expect(find.text('Default'), findsOneWidget, reason: 'the menu stays open');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a pre-launch task is noted under the configuration', (tester) async {
      await pumpTab(tester);
      await openMenu(tester);

      expect(find.text('pre-launch task is skipped'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('an unreadable file shows one row, and Default keeps working', (tester) async {
      configs.launch[1] = const LaunchConfigsUnreadable(
        LaunchUnreadableKind.invalidJson,
        'Unexpected character',
      );
      await pumpTab(tester);
      await openMenu(tester);

      expect(
        find.text("launch.json can't be read: invalid JSON: Unexpected character"),
        findsOneWidget,
      );
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Run DEV'), findsNothing);

      await tester.tap(find.text("launch.json can't be read: invalid JSON: Unexpected character"));
      await tester.pumpAndSettle();
      expect(find.text('Default'), findsOneWidget, reason: 'the row is disabled');

      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Run'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(scripted().starts, hasLength(1));
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('every unreadable kind has its own reason', (tester) async {
      const expected = <LaunchUnreadableKind, String>{
        LaunchUnreadableKind.notAnObject: "launch.json can't be read: not a JSON object",
        LaunchUnreadableKind.noConfigurationsList:
            "launch.json can't be read: no configurations list",
        LaunchUnreadableKind.cannotRead: "launch.json can't be read: cannot read the file: denied",
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        configs.launch[1] = LaunchConfigsUnreadable(
          key,
          key == LaunchUnreadableKind.cannotRead ? 'denied' : null,
        );
        await pumpTab(tester);
        await openMenu(tester);
        expect(find.text(value), findsOneWidget, reason: key.name);
        await disposeTestApp(tester, dependencies);
        // A fresh tab for the next kind.
        run.dispose();
        run = RunController(
          repository: dependencies.appRunRepository,
          configRepository: dependencies.runConfigRepository,
        );
      }
    });

    testWidgets('a missing file offers Create launch.json, which writes it and opens it', (
      tester,
    ) async {
      configs.launch.remove(1);
      await pumpTab(tester);
      await openMenu(tester);

      expect(find.text('Open launch.json'), findsNothing);
      await tester.tap(find.text('Create launch.json'));
      await tester.pumpAndSettle();
      // The file system answers on the real event loop; the code that waits for it runs on the
      // test's.
      for (var i = 0; i < 20 && openedFiles.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }

      final file = File(launchJsonPath(root.path));
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), '{"version": "0.2.0", "configurations": []}\n');
      expect(openedFiles, <(String, int?)>[(launchJsonPath(root.path), null)]);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('an existing file offers Open launch.json, which opens it', (tester) async {
      await pumpTab(tester);
      await openMenu(tester);

      expect(find.text('Create launch.json'), findsNothing);
      await tester.tap(find.text('Open launch.json'));
      await tester.pumpAndSettle();

      expect(openedFiles, <(String, int?)>[(launchJsonPath(root.path), null)]);
      expect(File(launchJsonPath(root.path)).existsSync(), isFalse, reason: 'nothing is written');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a configuration whose device is not connected disables Run with the reason', (
      tester,
    ) async {
      await pumpTab(tester);
      run.chooseConfig('Run Web');
      await tester.pump();
      expect(run.state.selectedDeviceId, 'web-server');

      expect(find.byTooltip("Device web-server isn't available"), findsOneWidget);
      expect(find.text("Device web-server isn't available"), findsOneWidget);
      await tester.tap(find.text('Run · Run Web'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 20));
      expect(scripted().starts, isEmpty);

      // The user's own device chip wins afterwards.
      run.choose(deviceId: 'macos');
      await tester.pump();
      await tester.tap(find.text('Run · Run Web'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(scripted().starts, hasLength(1));
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a configuration run passes its flavor', (tester) async {
      await pumpTab(tester);
      run.chooseConfig('Run DEV');
      await tester.pump();

      await tester.tap(find.text('Run · Run DEV'));
      await tester.pump(const Duration(milliseconds: 20));

      expect(scripted().starts.single.arguments.flavor, 'dev');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('while running the main part is Stop and the menu still opens', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.byTooltip('Run'));
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.byTooltip('Stop the app'), findsOneWidget);
      expect(find.byTooltip('Run'), findsNothing);

      await openMenu(tester);
      expect(find.text('Default'), findsOneWidget);
      await tester.tap(find.text('Run DEV'));
      await tester.pumpAndSettle();
      expect(run.state.selectedConfig, 'Run DEV', reason: 'it counts from the next start');
      expect(find.byTooltip('Stop the app'), findsOneWidget, reason: 'the run goes on');

      await tester.tap(find.byTooltip('Stop the app'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byTooltip('Run · Run DEV'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the Russian strings render', (tester) async {
      configs.launch[1] = const LaunchConfigsRead(<LaunchConfig>[
        _dev,
        _web,
        _broken,
        _elsewhere,
        _pre,
      ]);
      await pumpTab(tester, locale: const Locale('ru'));
      expect(find.text('Запустить'), findsOneWidget);

      run.chooseConfig('Run Web');
      await tester.pump();
      expect(find.text('Запустить · Run Web'), findsOneWidget);
      expect(find.byTooltip('Устройство web-server недоступно'), findsOneWidget);

      await openMenu(tester, 'Конфигурация запуска');
      expect(find.text('Default'), findsOneWidget);
      expect(find.text(r'Не поддерживается: ${env:HOME}'), findsOneWidget);
      expect(find.text('Не поддерживается: cwd /other вне проекта'), findsOneWidget);
      expect(find.text('задача перед запуском пропускается'), findsOneWidget);
      expect(find.text('Открыть launch.json'), findsOneWidget);
      await tester.tapAt(const Offset(1200, 700));
      await tester.pumpAndSettle();

      configs.launch[1] = const LaunchConfigsUnreadable(LaunchUnreadableKind.invalidJson, 'oops');
      await openMenu(tester, 'Конфигурация запуска');
      expect(find.text('launch.json не читается: некорректный JSON: oops'), findsOneWidget);
      await tester.tapAt(const Offset(1200, 700));
      await tester.pumpAndSettle();

      configs.launch.remove(1);
      await openMenu(tester, 'Конфигурация запуска');
      expect(find.text('Создать launch.json'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });
  });
}
