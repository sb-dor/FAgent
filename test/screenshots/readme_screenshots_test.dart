import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/session_event.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_completion.dart';
import 'package:flutter_code_agent/src/common/dart_analysis/models/dart_diagnostic.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_info.dart';
import 'package:flutter_code_agent/src/feature/agents/models/custom_agent_draft.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/data/flutter_sdk_repository_impl.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/skills/models/knowledge_item.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_chat_area.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_right_pane.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../support/memory_agents_repository.dart';
import '../support/memory_code_files_repository.dart';
import '../support/memory_dart_analysis_repository.dart';
import '../support/memory_devices_repository.dart';
import '../support/memory_project_creation_repository.dart';
import '../support/memory_skills_repository.dart';
import '../support/scripted_app_run_repository.dart';
import '../support/scripted_widget_picker_repository.dart';
import '../support/test_app.dart';

/// Renders the README screenshots in `docs/images/` from the real widgets with real fonts.
///
/// Opt-in, macOS only (it loads the system fonts the app has there):
/// `FLUTTER_SCREENSHOTS=1 flutter test test/screenshots/readme_screenshots_test.dart`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final enabled = io.Platform.environment['FLUTTER_SCREENSHOTS'] == '1';

  void screenshot(String description, Future<void> Function(WidgetTester tester) body) =>
      testWidgets(description, (tester) async {
        await _loadFonts(tester);
        WidgetsApp.debugAllowBannerOverride = false;
        addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
        tester.view
          ..physicalSize = _logicalSize * _pixelRatio
          ..devicePixelRatio = _pixelRatio;
        addTearDown(tester.view.reset);
        await body(tester);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  group('README screenshots', skip: enabled ? false : 'Run with FLUTTER_SCREENSHOTS=1', () {
    for (final dark in <bool>[false, true]) {
      screenshot('chat${dark ? '-dark' : ''}.png: a chat with edits, a plan and the diff', (
        tester,
      ) async {
        final dependencies = _dependencies();
        final seeded = await _seedProjects(tester, dependencies);
        await _seedChat(tester, dependencies, seeded.chat);
        await _pumpWorkspace(tester, dependencies, dark: dark);
        await _openChat(tester, seeded);
        await _collapseToolCalls(tester);
        _workspace(tester).openChange('$_shopRoot/$_screenFile');
        await _settle(tester);
        await _capture(tester, dark ? 'chat-dark' : 'chat');
        await disposeTestApp(tester, dependencies);
      });
    }

    screenshot('run.png: the Run tab with a running app, its logs and a picked widget', (
      tester,
    ) async {
      final run = ScriptedAppRunRepository();
      final dependencies = _dependencies(
        appRun: run,
        picker: ScriptedWidgetPickerRepository(
          step: const Duration(milliseconds: 1),
          result: const PickPicked(_orderTile),
        ),
      );
      final seeded = await _seedProjects(tester, dependencies, rightPaneWidth: 520);
      await _seedChat(tester, dependencies, seeded.chat);
      _seedRun(run, seeded.shop);
      await _pumpWorkspace(tester, dependencies);
      await _openChat(tester, seeded);
      await _collapseToolCalls(tester);
      _workspace(tester).dataController.selectPaneTab(RightPaneTab.run);
      await _settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(WorkspaceRightPane),
          matching: find.byTooltip('Pick a widget in the app'),
        ),
      );
      await _settle(tester);
      await _capture(tester, 'run');
      await disposeTestApp(tester, dependencies);
    });

    screenshot('code.png: the Code view with a Dart file, diagnostics and completions', (
      tester,
    ) async {
      final dependencies = _dependencies();
      final seeded = await _seedProjects(tester, dependencies, rightPane: false);
      await _pumpWorkspace(tester, dependencies);
      await _openChat(tester, seeded);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('code-view-switch')),
          matching: find.text('Code'),
        ),
      );
      await _settle(tester);
      final workspace = dependencies.codeViews.workspaceFor(
        projectId: seeded.shop,
        root: _shopRoot,
      );
      final analysis = workspace.analysis! as MemoryDartAnalysisRepository
        ..onComplete = (path, text, position) => _completions;
      await tester.runAsync(() => workspace.tabs.open('$_shopRoot/$_controllerFile'));
      await _settle(tester);
      final screen = (await tester.runAsync(() => workspace.tabs.open('$_shopRoot/$_screenFile')))!;
      workspace.tree.reveal('$_shopRoot/$_screenFile');
      await _settle(tester);
      // Types the start of `refresh` after `controller.` so the completion list opens.
      await tester.tap(find.byType(CodeEditor));
      await tester.pump();
      final typedAt = _screenSource.split('\n')[_completionLine].length;
      screen.editing.selection = CodeLineSelection.collapsed(
        index: _completionLine,
        offset: typedAt,
      );
      await tester.pump();
      screen.editing.replaceSelection('re');
      await _settle(tester);
      analysis.push(
        DartFileDiagnostics('$_shopRoot/$_screenFile', <DartDiagnostic>[
          _diagnostic(
            DartSeverity.warning,
            line: 5,
            start: 7,
            end: 55,
            message: "Unused import: 'package:shop_app/src/common/widget/empty_view.dart'.",
            code: 'unused_import',
          ),
          _diagnostic(
            DartSeverity.error,
            line: _completionLine,
            start: typedAt,
            end: typedAt + 2,
            message: "The getter 're' isn't defined for the type 'OrdersController'.",
            code: 'undefined_getter',
          ),
        ]),
      );
      await _settle(tester);
      await _capture(tester, 'code');
      await disposeTestApp(tester, dependencies);
    });

    screenshot('rules.png: the built-in rules with the link to the community chat', (tester) async {
      final dependencies = _dependencies();
      await _seedProjects(tester, dependencies);
      await _pumpWorkspace(tester, dependencies);
      _workspace(tester).dataController.openView(WorkspaceView.skills, section: 'rules');
      await _settle(tester);
      await tester.tap(find.text('architecture'));
      await _settle(tester);
      await _capture(tester, 'rules');
      await disposeTestApp(tester, dependencies);
    });

    screenshot('new-project.png: the new project wizard', (tester) async {
      final dependencies = _dependencies();
      final seeded = await _seedProjects(tester, dependencies);
      await _seedChat(tester, dependencies, seeded.chat);
      await _pumpWorkspace(tester, dependencies);
      await _openChat(tester, seeded);
      await _collapseToolCalls(tester);
      await tester.tap(find.text('Project'));
      await _settle(tester);
      await tester.tap(find.text('New Flutter project…'));
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey<String>('new-project-name')), 'loyalty_app');
      await _settle(tester);
      await _capture(tester, 'new-project');
      await disposeTestApp(tester, dependencies);
    });

    screenshot('settings.png: the agents page', (tester) async {
      final dependencies = _dependencies();
      final seeded = await _seedProjects(tester, dependencies);
      await _pumpWorkspace(tester, dependencies);
      await _openChat(tester, seeded);
      _workspace(tester).dataController.openView(WorkspaceView.settings, section: 'agents');
      await _settle(tester);
      await _capture(tester, 'settings');
      await disposeTestApp(tester, dependencies);
    });
  });
}

// ---------------------------------------------------------------------------------------------
// Rendering

/// The window in logical pixels.
const Size _logicalSize = Size(1280, 800);

/// Pixels per logical pixel of the PNGs.
const double _pixelRatio = 2;

/// Where the PNGs go.
const String _outputDirectory = 'docs/images';

const String _systemFonts = '/System/Library/Fonts';

/// The family the theme's text gets: San Francisco, the font the app has on macOS.
const String _uiFamily = 'SF Pro';

/// Fonts for glyphs the UI font does not have (⌘, ⇧, ⓧ, ⚠, emoji).
const List<String> _fallbackFamilies = <String>[
  'Arial Unicode',
  'Apple Symbols',
  'Apple Color Emoji',
];

bool _fontsLoaded = false;

/// Loads the fonts once per run; the test binding draws any family it does not know with boxes.
Future<void> _loadFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  await tester.runAsync(() async {
    Future<void> load(String family, List<String> paths) async {
      final loader = FontLoader(family);
      for (final path in paths) {
        final bytes = await io.File(path).readAsBytes();
        loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }

    // The tester runs from `<flutter>/bin/cache/artifacts/engine/…`.
    final executable = io.Platform.resolvedExecutable;
    final flutterRoot = executable.substring(0, executable.indexOf('/bin/cache/'));
    await load(_uiFamily, <String>['$_systemFonts/SFNS.ttf']);
    await load('MaterialIcons', <String>[
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
    await load(AppText.monoFamily, <String>[
      'assets/fonts/JetBrainsMono-Regular.ttf',
      'assets/fonts/JetBrainsMono-Medium.ttf',
    ]);
    await load('Menlo', <String>['$_systemFonts/Menlo.ttc']);
    // Inline code in the agent's markdown.
    await load('monospace', <String>['$_systemFonts/Menlo.ttc']);
    await load('Arial Unicode', <String>['/Library/Fonts/Arial Unicode.ttf']);
    await load('Apple Symbols', <String>['$_systemFonts/Apple Symbols.ttf']);
    await load('Apple Color Emoji', <String>['$_systemFonts/Apple Color Emoji.ttc']);
  });
}

ThemeData _withFonts(ThemeData theme) => theme.copyWith(
  textTheme: theme.textTheme.apply(fontFamily: _uiFamily, fontFamilyFallback: _fallbackFamilies),
  primaryTextTheme: theme.primaryTextTheme.apply(
    fontFamily: _uiFamily,
    fontFamilyFallback: _fallbackFamilies,
  ),
);

const ValueKey<String> _boundary = ValueKey<String>('screenshot');

WorkspaceConfigWidgetState _workspace(WidgetTester tester) =>
    WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

/// Lets drift's real-async work finish, then rebuilds; the composer's cursor never settles.
Future<void> _settle(WidgetTester tester, {int times = 4}) async {
  for (var i = 0; i < times; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpWorkspace(
  WidgetTester tester,
  Dependencies dependencies, {
  bool dark = false,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: testApp(
        const WorkspaceConfigWidget(),
        dependencies: dependencies,
        withSettings: true,
        theme: _withFonts(dark ? AppTheme.dark() : AppTheme.light()),
      ),
    ),
  );
  await _settle(tester);
}

/// Writes what is on screen to `docs/images/<name>.png`.
Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = io.File('$_outputDirectory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

// ---------------------------------------------------------------------------------------------
// Sample data

const String _shopRoot = '/Users/dev/StudioProjects/shop_app';
const String _screenFile = 'lib/src/feature/orders/widgets/orders_screen.dart';
const String _controllerFile = 'lib/src/feature/orders/controller/orders_controller.dart';
const String _testFile = 'test/feature/orders/orders_screen_test.dart';

/// Dependencies with real-looking run, devices and agents (no Preview badges), the sample project
/// files and the built-in rules.
Dependencies _dependencies({ScriptedAppRunRepository? appRun, IWidgetPickerRepository? picker}) {
  final files = MemoryCodeFilesRepository(files: _projectFiles);
  return testDependencies(
    appRunRepository: appRun ?? ScriptedAppRunRepository(),
    devicesRepository: MemoryDevicesRepository(step: const Duration(milliseconds: 1)),
    widgetPickerRepository: picker,
    codeFilesRepository: files,
    agentsRepository: MemoryAgentsRepository(agents: _agents),
    skillsRepository: MemorySkillsRepository(
      items: _builtinKnowledge(),
      texts: <String, String>{
        for (final rule in _ruleFiles()) 'rule:builtin:${_ruleName(rule)}': rule.readAsStringSync(),
      },
    ),
    projectCreationRepository: MemoryProjectCreationRepository(parent: '/Users/dev/StudioProjects'),
    flutterSdkRepository: FlutterSdkRepositoryImpl(
      which: (_) => '/Users/dev/development/flutter/bin/flutter',
      runProcess: (executable, arguments, {environment}) async =>
          io.ProcessResult(1, 0, '{"frameworkVersion":"3.47.9","channel":"stable"}', ''),
      step: Duration.zero,
    ),
  );
}

typedef _Seeded = ({int shop, int chat});

/// Three projects with a few chats each; returns the shop project and its newest chat.
Future<_Seeded> _seedProjects(
  WidgetTester tester,
  Dependencies dependencies, {
  double rightPaneWidth = 440,
  bool rightPane = true,
}) async => (await tester.runAsync(() async {
  await AppSettingsRepositoryImpl(database: dependencies.database)
      .update(AppSettings(rightPaneVisible: rightPane, rightPaneWidth: rightPaneWidth));
  final database = dependencies.database;
  Future<int> project(String name) => database
      .into(database.projectsTable)
      .insert(ProjectsTableCompanion.insert(path: '/Users/dev/StudioProjects/$name', name: name));
  final now = DateTime.now();
  Future<int> chat(int projectId, String title, int minutesAgo, {String agent = 'claude'}) =>
      database
          .into(database.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: projectId,
              agentId: agent,
              title: Value<String>(title),
              updatedAt: Value<DateTime>(now.subtract(Duration(minutes: minutesAgo))),
            ),
          );
  final shop = await project('shop_app');
  final delivery = await project('delivery_tracker');
  final weather = await project('weather_widgets');
  final main = await chat(shop, 'Add pull-to-refresh to the orders list', 1);
  await chat(shop, 'Fix the checkout button overflow', 90);
  await chat(shop, 'Migrate navigation to go_router', 60 * 26, agent: 'codex');
  await chat(delivery, 'Show the courier on the map', 60 * 5);
  await chat(delivery, 'Queue status updates while offline', 60 * 30, agent: 'gemini');
  await chat(weather, 'Home screen widget for iOS', 60 * 50);
  return (shop: shop, chat: main);
}))!;

Future<void> _openChat(WidgetTester tester, _Seeded seeded) async {
  _workspace(tester).dataController
    ..selectProject(seeded.shop)
    ..selectSession(seeded.chat);
  await _settle(tester, times: 6);
}

/// Folds the edit cards of the chat (they start expanded), so the whole turn fits the window.
Future<void> _collapseToolCalls(WidgetTester tester) async {
  final buttons = find.descendant(
    of: find.byType(WorkspaceChatArea),
    matching: find.widgetWithIcon(IconButton, Icons.expand_less),
  );
  // The feed builds lazily: a card above comes into view once the ones below are folded.
  for (var round = 0; round < 6 && buttons.evaluate().isNotEmpty; round++) {
    for (final button in tester.widgetList<IconButton>(buttons).toList()) {
      button.onPressed!();
    }
    await _settle(tester);
  }
}

/// The journal of the hero chat, as an ACP agent would have written it.
Future<void> _seedChat(WidgetTester tester, Dependencies dependencies, int sessionId) =>
    tester.runAsync(() async {
      final live = await dependencies.agentHub.session(sessionId);
      Future<void> add(String kind, Map<String, Object?> payload, {bool user = false}) => live.store
          .addDurable(user ? SessionEventOrigin.user : SessionEventOrigin.agent, kind, payload);
      Future<void> update(String kind, Map<String, Object?> update) => add(kind, <String, Object?>{
        'params': <String, Object?>{
          'update': <String, Object?>{'sessionUpdate': kind, ...update},
        },
      });
      Future<void> message(String id, String text) =>
          update('agent_message_chunk', <String, Object?>{
            'messageId': id,
            'content': <String, Object?>{'type': 'text', 'text': text},
          });
      Map<String, Object?> location(String path) => <String, Object?>{'path': '$_shopRoot/$path'};

      await add(SessionEventKind.prompt, <String, Object?>{
        'prompt': <Object?>[
          <String, Object?>{
            'type': 'text',
            'text': 'Add pull-to-refresh to the orders list; show a snackbar when a refresh fails.',
          },
        ],
      }, user: true);
      await message(
        'm1',
        "I'll check how the orders list loads first, then wire a `RefreshIndicator` to the "
            'controller.',
      );
      for (final (id, path) in <(String, String)>[
        ('r1', _screenFile),
        ('r2', _controllerFile),
        ('r3', 'lib/src/feature/orders/data/orders_repository.dart'),
      ]) {
        await update('tool_call', <String, Object?>{
          'toolCallId': id,
          'title': 'Read $path',
          'kind': 'read',
          'status': 'completed',
          'locations': <Object?>[location(path)],
        });
      }
      await update('plan', <String, Object?>{
        'entries': <Object?>[
          for (final step in <String>[
            'Add refresh() to OrdersController that keeps the loaded orders',
            'Wrap the orders list in a RefreshIndicator',
            'Cover pull-to-refresh with a widget test',
          ])
            <String, Object?>{'content': step, 'priority': 'medium', 'status': 'completed'},
        ],
      });
      await update('tool_call', <String, Object?>{
        'toolCallId': 'e1',
        'title': 'Edit $_controllerFile',
        'kind': 'edit',
        'status': 'completed',
        'locations': <Object?>[location(_controllerFile)],
        'content': <Object?>[
          <String, Object?>{
            'type': 'diff',
            'path': '$_shopRoot/$_controllerFile',
            'oldText': _controllerBefore,
            'newText': _controllerAfter,
          },
        ],
      });
      await update('tool_call', <String, Object?>{
        'toolCallId': 'e2',
        'title': 'Edit $_screenFile',
        'kind': 'edit',
        'status': 'completed',
        'locations': <Object?>[location(_screenFile)],
        'content': <Object?>[
          <String, Object?>{
            'type': 'diff',
            'path': '$_shopRoot/$_screenFile',
            'oldText': _screenBefore,
            'newText': _screenAfter,
          },
        ],
      });
      await update('tool_call', <String, Object?>{
        'toolCallId': 'e3',
        'title': 'Write $_testFile',
        'kind': 'edit',
        'status': 'completed',
        'locations': <Object?>[location(_testFile)],
        'content': <Object?>[
          <String, Object?>{
            'type': 'diff',
            'path': '$_shopRoot/$_testFile',
            'oldText': null,
            'newText': _testSource,
          },
        ],
      });
      await update('tool_call', <String, Object?>{
        'toolCallId': 'x1',
        'title': 'flutter test test/feature/orders',
        'kind': 'execute',
        'status': 'completed',
        'rawInput': <String, Object?>{'command': 'flutter test test/feature/orders'},
      });
      await update('tool_call_update', <String, Object?>{
        'toolCallId': 'x1',
        'status': 'completed',
        'rawOutput': '00:04 +6: All tests passed!',
      });
      await message(
        'm2',
        'Done. Pulling the orders list down now calls `OrdersController.refresh()`:\n\n'
            '- the first load still shows the spinner; a refresh keeps the current orders on '
            'screen\n'
            '- a failed refresh keeps the old list and shows a snackbar with the error\n'
            '- `orders_screen_test.dart` drags the list and checks both cases; the tests pass',
      );
      await add(SessionEventKind.system, <String, Object?>{
        'type': 'turn_end',
        'stopReason': 'end_turn',
      });
    });

const Device _iphone = Device(
  id: 'ios-sim-16-pro',
  name: 'iPhone 16 Pro',
  platform: DevicePlatform.ios,
  kind: DeviceKind.running,
  detail: 'Simulator',
);

const PickedWidget _orderTile = PickedWidget(
  name: 'OrderTile',
  file: 'lib/src/feature/orders/widgets/order_tile.dart',
  line: 28,
  column: 12,
  id: 'inspector-order-tile',
  ancestors: <PickedAncestor>[
    PickedAncestor(
      name: 'OrdersList',
      file: 'lib/src/feature/orders/widgets/orders_list.dart',
      line: 19,
      column: 14,
      id: 'inspector-orders-list',
    ),
    PickedAncestor(
      name: 'OrdersScreen',
      file: 'lib/src/feature/orders/widgets/orders_screen.dart',
      line: 34,
      column: 12,
      id: 'inspector-orders-screen',
    ),
  ],
);

/// A debug run on the iPhone simulator, a few minutes in, after a hot reload and an overflow.
void _seedRun(ScriptedAppRunRepository run, int projectId) {
  void log(String text, {LogLevel level = LogLevel.info, RunError? error}) =>
      run.addLog(projectId, level, text, error: error);
  log('Launching lib/main.dart on iPhone 16 Pro in debug mode...');
  log('Running Xcode build...');
  log('Xcode build done.                                           21.7s');
  log('Syncing files to device iPhone 16 Pro...                     188ms');
  log('flutter: [Orders] loaded 24 orders in 312 ms');
  log('flutter: [Orders] refresh → 24 orders');
  log('Reloaded 2 of 1186 libraries in 274ms (compile: 38 ms, reload: 121 ms, reassemble: 98 ms).');
  log('flutter: [Orders] refresh → 25 orders (1 new)');
  log(
    'Image provider: NetworkImage("https://cdn.shop.example/p/4127.jpg", scale: 1.0) is slow',
    level: LogLevel.warning,
  );
  const message = 'A RenderFlex overflowed by 18 pixels on the right.';
  log(
    message,
    level: LogLevel.error,
    error: const RunError(
      title: 'Layout overflow',
      message: message,
      location: 'order_tile.dart:28:12',
      file: 'lib/src/feature/orders/widgets/order_tile.dart',
      line: 28,
      stack:
          '#0 RenderFlex.paint (package:flutter/src/rendering/flex.dart:1163:9)\n'
          '#1 OrderTile.build (package:shop_app/src/feature/orders/widgets/order_tile.dart:28:12)',
    ),
  );
  run.setRunState(
    projectId,
    RunRunning(
      device: _iphone,
      startedAt: DateTime.now().subtract(const Duration(minutes: 4, seconds: 12)),
      vmServiceUri: ScriptedAppRunRepository.vmServiceUri,
      devToolsUri: ScriptedAppRunRepository.devToolsUri,
      lastReload: const Duration(milliseconds: 274),
    ),
  );
}

const List<AgentInfo> _agents = <AgentInfo>[
  AgentInfo(
    id: 'claude',
    name: 'Claude Code',
    version: '0.96.0',
    runtime: 'Node 22.11',
    status: AgentStatus.ready,
    account: 'Claude Max',
    canSignOut: true,
  ),
  AgentInfo(
    id: 'codex',
    name: 'Codex',
    version: '2.5.0',
    runtime: 'Node 22.11',
    status: AgentStatus.ready,
    account: 'ChatGPT Plus',
    canSignOut: true,
  ),
  AgentInfo(
    id: 'gemini',
    name: 'Gemini CLI',
    version: '0.66.0',
    runtime: 'Node 22.11',
    status: AgentStatus.needsLogin,
    methods: <AgentLoginMethod>[
      AgentLoginMethod(
        id: 'oauth-personal',
        name: 'Log in with Google',
        kind: AgentLoginKind.browser,
      ),
    ],
  ),
  AgentInfo(
    id: 'custom:1',
    name: 'OpenCode',
    status: AgentStatus.ready,
    source: AgentSource.custom,
    custom: CustomAgentDraft(
      name: 'OpenCode',
      executable: '/opt/homebrew/bin/opencode',
      arguments: <String>['acp'],
    ),
  ),
];

/// The built-in rules of `assets/knowledge/rules/`, by name.
List<io.File> _ruleFiles() =>
    io.Directory('assets/knowledge/rules')
        .listSync()
        .whereType<io.File>()
        .where((file) => file.path.endsWith('.md'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

String _frontmatter(io.File file, String field) {
  final match = RegExp('^$field: (.*)\$', multiLine: true).firstMatch(file.readAsStringSync());
  final value = match?.group(1)?.trim() ?? '';
  return value.startsWith('"') ? value.substring(1, value.length - 1) : value;
}

String _ruleName(io.File file) => _frontmatter(file, 'name');

/// The built-in rules with their names and descriptions, and two skills.
List<KnowledgeItem> _builtinKnowledge() => <KnowledgeItem>[
  memorySkill('feature-architecture', description: 'A new feature in the project layout'),
  memorySkill('widget-test', description: 'Writes a widget test for a screen'),
  for (final file in _ruleFiles())
    memoryRule(_ruleName(file), description: _frontmatter(file, 'description')),
];

DartDiagnostic _diagnostic(
  DartSeverity severity, {
  required int line,
  required int start,
  required int end,
  required String message,
  required String code,
}) => DartDiagnostic(
  range: LspRange(
    start: LspPosition(line: line, character: start),
    end: LspPosition(line: line, character: end),
  ),
  severity: severity,
  message: message,
  code: code,
);

const List<DartCompletion> _completions = <DartCompletion>[
  DartCompletion(
    label: 'refresh',
    kind: DartCompletionKind.method,
    insertText: 'refresh',
    detail: 'Future<void> Function()',
    sortText: '1',
  ),
  DartCompletion(
    label: 'retry',
    kind: DartCompletionKind.method,
    insertText: 'retry',
    detail: 'void Function()',
    sortText: '2',
  ),
  DartCompletion(
    label: 'removeListener',
    kind: DartCompletionKind.method,
    insertText: 'removeListener',
    detail: 'void Function(VoidCallback listener)',
    sortText: '3',
  ),
  DartCompletion(
    label: 'repository',
    kind: DartCompletionKind.field,
    insertText: 'repository',
    detail: 'IOrdersRepository',
    sortText: '4',
  ),
];

/// The line of [_screenSource] that ends in `controller.`, where the completion opens.
final int _completionLine = _screenSource
    .split('\n')
    .indexWhere((line) => line.endsWith('controller.'));

const String _controllerBefore = '''
  Future<void> load() => handle(() async {
    setState(const OrdersState.loading());
    final orders = await _repository.fetchOrders();
    setState(OrdersState.loaded(orders));
  });
''';

const String _controllerAfter = '''
  Future<void> load() => handle(() async {
    setState(const OrdersState.loading());
    final orders = await _repository.fetchOrders();
    setState(OrdersState.loaded(orders));
  });

  /// Loads the orders again and keeps the current ones on screen meanwhile.
  Future<void> refresh() => handle(
    () async {
      final orders = await _repository.fetchOrders(forceRefresh: true);
      setState(OrdersState.loaded(orders));
    },
    error: (error, _) async => setState(state.copyWith(refreshError: error)),
  );
''';

const String _screenBefore = '''
    body: StateConsumer<OrdersController, OrdersState>(
      controller: controller,
      builder: (context, state, _) {
        return switch (state) {
          OrdersLoading() => const Center(child: CircularProgressIndicator()),
          OrdersLoaded(:final orders) => OrdersList(orders: orders),
        };
      },
    ),
  );
}
''';

const String _screenAfter = '''
    body: StateConsumer<OrdersController, OrdersState>(
      controller: controller,
      listener: (context, controller, previous, current) {
        if (current.refreshError case final error?) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Localization.of(context).ordersRefreshFailed(error))),
          );
        }
      },
      builder: (context, state, _) {
        return switch (state) {
          OrdersLoading() => const Center(child: CircularProgressIndicator()),
          OrdersLoaded(:final orders) => RefreshIndicator(
            onRefresh: controller.refresh,
            child: OrdersList(
              orders: orders,
              physics: const AlwaysScrollableScrollPhysics(),
            ),
          ),
        };
      },
    ),
  );
}
''';

const String _testSource = '''
void main() {
  testWidgets('pulling the list down refreshes the orders', (tester) async {
    final repository = FakeOrdersRepository(orders: [order(1), order(2)]);
    await tester.pumpWidget(testApp(OrdersScreen(repository: repository)));
    await tester.pumpAndSettle();

    repository.orders = [order(1), order(2), order(3)];
    await tester.fling(find.byType(OrdersList), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(OrderTile), findsNWidgets(3));
  });
}
''';

const String _screenSource = '''
import 'package:flutter/material.dart';
import 'package:shop_app/src/common/localization/localization.dart';
import 'package:shop_app/src/feature/orders/controller/orders_controller.dart';
import 'package:shop_app/src/feature/orders/controller/orders_state.dart';
import 'package:shop_app/src/feature/orders/widgets/orders_list.dart';
import 'package:shop_app/src/common/widget/empty_view.dart';

/// {@template orders_screen}
/// The orders of the signed-in customer, newest first.
/// {@endtemplate}
class OrdersScreen extends StatelessWidget {
  /// {@macro orders_screen}
  const OrdersScreen({required this.controller, super.key});

  /// Loads and refreshes the orders.
  final OrdersController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(Localization.of(context).ordersTitle)),
    body: StateConsumer<OrdersController, OrdersState>(
      controller: controller,
      listener: (context, controller, previous, current) {
        if (current.refreshError case final error?) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Localization.of(context).ordersRefreshFailed(error))),
          );
        }
      },
      builder: (context, state, _) => switch (state) {
        OrdersLoading() => const Center(child: CircularProgressIndicator()),
        OrdersLoaded(:final orders) => RefreshIndicator(
          onRefresh: controller.
          child: OrdersList(
            orders: orders,
            physics: const AlwaysScrollableScrollPhysics(),
          ),
        ),
      },
    ),
  );
}
''';

/// The files of `shop_app` the Code view lists.
final Map<String, String> _projectFiles = <String, String>{
  '$_shopRoot/pubspec.yaml': 'name: shop_app\n',
  '$_shopRoot/README.md': '# shop_app\n',
  '$_shopRoot/analysis_options.yaml': 'include: package:flutter_lints/flutter.yaml\n',
  '$_shopRoot/lib/main.dart': 'void main() {}\n',
  '$_shopRoot/lib/src/common/widget/empty_view.dart': '\n',
  '$_shopRoot/lib/src/feature/cart/widgets/cart_screen.dart': '\n',
  '$_shopRoot/lib/src/feature/catalog/widgets/catalog_screen.dart': '\n',
  '$_shopRoot/lib/src/feature/orders/controller/orders_state.dart': '\n',
  '$_shopRoot/$_controllerFile': 'final class OrdersController {\n$_controllerAfter}\n',
  '$_shopRoot/lib/src/feature/orders/data/orders_repository.dart': '\n',
  '$_shopRoot/lib/src/feature/orders/models/order.dart': '\n',
  '$_shopRoot/lib/src/feature/orders/widgets/order_tile.dart': '\n',
  '$_shopRoot/lib/src/feature/orders/widgets/orders_list.dart': '\n',
  '$_shopRoot/$_screenFile': _screenSource,
  '$_shopRoot/$_testFile': _testSource,
};
