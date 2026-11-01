import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_device_chip.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/controller/prompt_sending_controller.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/run_mentions.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/widgets/command_suggestions.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_run_controls.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_devices_repository.dart';
import '../../support/scripted_app_run_repository.dart';
import '../../support/test_app.dart';

/// The fake run that counts what the window asks it to do.
final class _SpyRunRepository implements IAppRunRepository {
  _SpyRunRepository() : _inner = ScriptedAppRunRepository(step: const Duration(milliseconds: 1));

  final ScriptedAppRunRepository _inner;
  final List<String> started = <String>[];

  /// The arguments each start was given.
  List<RunArguments> get startedArguments =>
      _inner.starts.map((start) => start.arguments).toList(growable: false);
  int reloads = 0;
  int restarts = 0;

  /// The fake run behind the spy, for what a test sets up on it.
  ScriptedAppRunRepository get scripted => _inner;

  @override
  RunState currentRun(int projectId) => _inner.currentRun(projectId);

  @override
  List<LogEntry> recentLogs(int projectId, {int limit = kRunLogLimit}) =>
      _inner.recentLogs(projectId, limit: limit);

  @override
  bool get isPreview => true;

  @override
  Stream<RunState> watchRun(int projectId) => _inner.watchRun(projectId);

  @override
  Stream<LogEntry> logs(int projectId) => _inner.logs(projectId);

  @override
  Future<void> markSent(int projectId, int seq) => _inner.markSent(projectId, seq);

  @override
  Future<void> start(
    int projectId, {
    required Device device,
    required BuildMode mode,
    required String target,
    RunArguments arguments = const RunArguments(),
  }) {
    started.add(device.id);
    return _inner.start(
      projectId,
      device: device,
      mode: mode,
      target: target,
      arguments: arguments,
    );
  }

  @override
  Future<void> stop(int projectId) => _inner.stop(projectId);

  @override
  Future<Duration> hotReload(int projectId) {
    reloads++;
    return _inner.hotReload(projectId);
  }

  @override
  Future<void> hotRestart(int projectId) {
    restarts++;
    return _inner.hotRestart(projectId);
  }

  @override
  Future<void> openDevTools(int projectId) => _inner.openDevTools(projectId);

  @override
  Future<String?> screenshot(int projectId) => _inner.screenshot(projectId);

  @override
  Future<void> dispose() => _inner.dispose();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late _SpyRunRepository spy;
  late MemoryDevicesRepository devices;
  late int projectId;
  late int sessionId;
  late int otherSessionId;

  setUp(() {
    spy = _SpyRunRepository();
    devices = MemoryDevicesRepository(step: const Duration(milliseconds: 1), isPreview: true);
    dependencies = testDependencies(appRunRepository: spy, devicesRepository: devices);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// A window with one project and one chat; the chat is opened when [openChat].
  Future<void> pumpShell(
    WidgetTester tester, {
    bool openChat = true,
    bool reloadAfterTurn = false,
  }) async {
    useDesktopView(tester);
    await tester.runAsync(() async {
      final database = dependencies.database;
      await AppSettingsRepositoryImpl(database: database)
          .update(AppSettings(reloadAfterTurn: reloadAfterTurn));
      projectId = await database
          .into(database.projectsTable)
          .insert(ProjectsTableCompanion.insert(path: '/p', name: 'p'));
      sessionId = await database
          .into(database.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: projectId,
              agentId: 'claude',
              title: const Value<String>('The chat'),
            ),
          );
      otherSessionId = await database
          .into(database.sessionsTable)
          .insert(
            SessionsTableCompanion.insert(
              projectId: projectId,
              agentId: 'claude',
              title: const Value<String>('Other chat'),
            ),
          );
    });
    await tester.pumpWidget(
      testApp(const WorkspaceConfigWidget(), dependencies: dependencies, withSettings: true),
    );
    await settle(tester);
    await tester.pumpAndSettle();
    if (openChat) {
      await tester.tap(find.text('The chat'));
    } else {
      await tester.tap(find.text('p').first);
    }
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
  }

  WorkspaceConfigWidgetState workspaceOf(WidgetTester tester) =>
      WorkspaceConfigInhWidget.of(tester.element(find.byType(WorkspaceWidget)));

  /// Waits (in real and fake time) until [condition] holds.
  Future<void> until(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 30 && !condition(); i++) {
      await settle(tester);
    }
    expect(condition(), isTrue);
  }

  bool running(WidgetTester tester) => workspaceOf(tester).runController.state.run is RunRunning;

  Future<void> startRun(WidgetTester tester) async {
    final workspace = workspaceOf(tester);
    await until(tester, () => workspace.selectedDevice != null);
    workspace.runActionsController.start(
      projectId,
      device: workspace.selectedDevice!,
      mode: BuildMode.debug,
      target: 'lib/main.dart',
    );
    await until(tester, () => running(tester));
  }

  ChatHandle handleWith(SessionStatus status) => ChatHandle(
    sessionId: sessionId,
    view: ChatView(sessionId: sessionId, agentId: 'claude', items: const [], status: status),
    insertDraft: (_) {},
  );

  Future<void> publish(
    WidgetTester tester,
    SessionStatus status, {
    ValueChanged<String>? insertDraft,
  }) async {
    workspaceOf(tester).dataController.publishChatHandle(
      ChatHandle(
        sessionId: workspaceOf(tester).dataController.sessionId!,
        view: handleWith(status).view,
        insertDraft: insertDraft ?? (_) {},
      ),
    );
    await settle(tester);
  }

  Future<void> pressShortcut(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await settle(tester);
  }

  /// Reloads once so the fake run reports its layout overflow, and returns that log line.
  Future<LogEntry> reloadUntilError(WidgetTester tester) async {
    final workspace = workspaceOf(tester);
    workspace.runActionsController.hotReload(projectId);
    await until(tester, () => workspace.runController.state.errorCount > 0);
    return workspace.runController.state.logs.firstWhere((log) => log.error != null);
  }

  group('send to agent', () {
    testWidgets('puts the error into the composer draft and marks the line as sent', (
      tester,
    ) async {
      await pumpShell(tester);
      await startRun(tester);
      final entry = await reloadUntilError(tester);
      final chat = tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));
      final workspace = workspaceOf(tester)..sendRunErrorToAgent(entry);
      await tester.pump();

      expect(chat.textController.text, contains('Layout overflow'));
      expect(chat.textController.text, contains('booking_card.dart:42'));
      expect(
        workspace.runController.state.logs.firstWhere((log) => log.seq == entry.seq).sentToAgent,
        isTrue,
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('while the chat is running it is still only a draft', (tester) async {
      await pumpShell(tester);
      await startRun(tester);
      final entry = await reloadUntilError(tester);
      final chat = tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));
      await publish(tester, SessionStatus.running, insertDraft: chat.insertDraft);
      final workspace = workspaceOf(tester);
      expect(workspace.dataController.chatHandle.value?.view.status, SessionStatus.running);

      workspace.sendRunErrorToAgent(entry);
      await settle(tester);

      expect(chat.textController.text, contains('Layout overflow'));
      expect(chat.promptController.state, isA<PromptSending$InitialState>());
      expect(
        workspace.runController.state.logs.firstWhere((log) => log.seq == entry.seq).sentToAgent,
        isTrue,
      );
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('without a chat, send to agent explains why', (tester) async {
      await pumpShell(tester, openChat: false);
      final entry = LogEntry(
        seq: 0,
        time: _epoch,
        level: LogLevel.error,
        text: 'boom',
        error: const RunError(title: 'Boom', message: 'boom'),
      );

      workspaceOf(tester).sendRunErrorToAgent(entry);
      await tester.pump();

      expect(find.text('Open a chat to send the error to the agent'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('add to message puts @widget into the draft', (tester) async {
      await pumpShell(tester);
      final chat = tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));

      workspaceOf(tester).addRunWidgetToMessage(
        const PickedWidget(
          name: 'BookingCard',
          file: 'lib/src/feature/booking/widgets/booking_card.dart',
          line: 42,
          ancestors: <String>[],
        ),
      );
      await tester.pump();

      expect(
        chat.textController.text,
        '@widget BookingCard (lib/src/feature/booking/widgets/booking_card.dart:42)',
      );
      await disposeTestApp(tester, dependencies);
    });
  });

  group('screenshot', () {
    const path = ScriptedAppRunRepository.defaultScreenshotPath;

    testWidgets('puts @path into the draft and offers it to the @ menu and to the send', (
      tester,
    ) async {
      await pumpShell(tester);
      await startRun(tester);
      final chat = tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));
      final workspace = workspaceOf(tester);
      expect(workspace.runLink.mentions?.screenshot, isNull);

      workspace.runActionsController.screenshot(projectId);
      await until(tester, () => chat.textController.text.isNotEmpty);

      expect(chat.textController.text, '@$path');
      final mentions = workspace.runLink.mentions!;
      expect(mentions.screenshot!.text, '@$path');
      expect(mentions.screenshot!.detail, matches(RegExp(r'^\d\d:\d\d:\d\d$')));
      expect(mentions.attachable, <String>{path});
      expect(find.byType(SnackBar), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('without a chat the path is remembered and the user is told to open one', (
      tester,
    ) async {
      await pumpShell(tester, openChat: false);
      workspaceOf(tester).dataController.selectProject(projectId);
      await settle(tester);
      expect(workspaceOf(tester).dataController.chatHandle.value, isNull);
      await startRun(tester);

      workspaceOf(tester).runActionsController.screenshot(projectId);
      await until(tester, () => workspaceOf(tester).runLink.mentions?.screenshot != null);
      await tester.pump();

      expect(find.text('Open a chat to add the screenshot to the message'), findsOneWidget);
      expect(workspaceOf(tester).runLink.mentions!.screenshot!.text, '@$path');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the @ menu keeps every shot of the session, the last one is the offer', (
      tester,
    ) async {
      await pumpShell(tester);
      await startRun(tester);
      final chat = tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));
      final workspace = workspaceOf(tester);

      workspace.runActionsController.screenshot(projectId);
      await until(tester, () => chat.textController.text.isNotEmpty);
      spy.scripted.screenshotPath = '.dart_tool/flutter_code_agent/screenshots/second.png';
      workspace.runActionsController.screenshot(projectId);
      await until(tester, () => workspace.runLink.mentions!.attachable.length == 2);

      final mentions = workspace.runLink.mentions!;
      expect(mentions.screenshot!.text, '@.dart_tool/flutter_code_agent/screenshots/second.png');
      expect(mentions.attachable, <String>{
        path,
        '.dart_tool/flutter_code_agent/screenshots/second.png',
      });
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a shot that failed puts nothing into the draft', (tester) async {
      await pumpShell(tester);
      await startRun(tester);
      spy.scripted.screenshotPath = null;
      final chat = tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));

      workspaceOf(tester).runActionsController.screenshot(projectId);
      await until(tester, () => spy.scripted.screenshotCalls.isNotEmpty);
      await settle(tester);

      expect(chat.textController.text, isEmpty);
      expect(workspaceOf(tester).runLink.mentions?.screenshot, isNull);
      expect(find.byType(SnackBar), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('DevTools opens through the repository', (tester) async {
      await pumpShell(tester);
      await startRun(tester);

      workspaceOf(tester).runActionsController.openDevTools(projectId);
      await until(tester, () => spy.scripted.devToolsOpened.isNotEmpty);

      expect(spy.scripted.devToolsOpened, <int>[projectId]);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('app commands', () {
    Finder row(String name) =>
        find.descendant(of: find.byType(CommandSuggestions), matching: find.text(name));

    /// Types [text] into the composer and presses Enter on the highlighted row.
    Future<void> choose(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
    }

    testWidgets('the offer tells what can be done: start with a device, the rest once running', (
      tester,
    ) async {
      await pumpShell(tester);
      final workspace = workspaceOf(tester);
      await until(tester, () => workspace.selectedDevice != null);

      var mentions = workspace.runLink.mentions!;
      expect((mentions.canStart, mentions.canReload, mentions.canScreenshot), (true, false, false));

      await startRun(tester);
      mentions = workspace.runLink.mentions!;
      expect((mentions.canStart, mentions.canReload, mentions.canScreenshot), (false, true, true));
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('/run starts the app on the chosen device and leaves the field empty', (
      tester,
    ) async {
      await pumpShell(tester);
      final workspace = workspaceOf(tester);
      await until(tester, () => workspace.runController.state.selectedDeviceId != null);
      final chat = tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));

      await choose(tester, '/run');

      expect(spy.started, <String?>[workspace.runController.state.selectedDeviceId]);
      expect(chat.textController.text, isEmpty);
      await until(tester, () => running(tester));
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('/run comes up once the chosen emulator has booted, with nothing else changing', (
      tester,
    ) async {
      await pumpShell(tester);
      final workspace = workspaceOf(tester);
      await until(tester, () => workspace.selectedDevice != null);
      workspace.chooseDevice('android-pixel-9');
      await settle(tester);
      RunMentions? offer() =>
          tester.widget<ChatConfigWidget>(find.byType(ChatConfigWidget)).runContext;
      expect(offer()!.canStart, isFalse, reason: 'the emulator is still booting');

      devices.set(<Device>[
        for (final device in kTestDevices)
          if (device.id == 'android-pixel-9')
            Device(
              id: device.id,
              name: device.name,
              platform: device.platform,
              kind: DeviceKind.running,
            )
          else
            device,
      ]);
      await settle(tester);

      expect(offer()!.canStart, isTrue);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('/reload and /restart act on the running app', (tester) async {
      await pumpShell(tester);
      await startRun(tester);
      final chat = tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));

      await choose(tester, '/reload');
      expect((spy.reloads, spy.restarts), (1, 0));
      await choose(tester, '/restart');
      expect((spy.reloads, spy.restarts), (1, 1));
      expect(chat.textController.text, isEmpty);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('/screenshot puts @path into the draft of the chat', (tester) async {
      await pumpShell(tester);
      await startRun(tester);
      final chat = tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));

      await choose(tester, '/screenshot');
      await until(tester, () => chat.textController.text.isNotEmpty);

      expect(chat.textController.text, '@${ScriptedAppRunRepository.defaultScreenshotPath}');
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('while the app is not running /reload and /screenshot are not available', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.enterText(find.byType(TextField), '/re');
      await tester.pump();

      expect(find.text('App is not running'), findsNWidgets(3));
      expect(row('/reload'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(spy.reloads, 0);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a running app is not started again by /run', (tester) async {
      await pumpShell(tester);
      await startRun(tester);
      final started = spy.started.length;

      await tester.enterText(find.byType(TextField), '/run');
      await tester.pump();
      expect(workspaceOf(tester).runLink.mentions!.canStart, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);

      expect(spy.started, hasLength(started));
      await disposeTestApp(tester, dependencies);
    });
  });

  group('reload after a turn', () {
    testWidgets('fires once per finished turn', (tester) async {
      await pumpShell(tester, reloadAfterTurn: true);
      await startRun(tester);

      await publish(tester, SessionStatus.running);
      expect(spy.reloads, 0);
      await publish(tester, SessionStatus.idle);
      expect(spy.reloads, 1);
      // The same status published again (a redraw of the chat) is not a new turn.
      await publish(tester, SessionStatus.idle);
      await publish(tester, SessionStatus.idle);
      expect(spy.reloads, 1);

      await publish(tester, SessionStatus.running);
      await publish(tester, SessionStatus.awaitingPermission);
      await publish(tester, SessionStatus.running);
      await publish(tester, SessionStatus.idle);
      await until(tester, () => spy.reloads == 2);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('does nothing when the turn ends in an error', (tester) async {
      await pumpShell(tester, reloadAfterTurn: true);
      await startRun(tester);

      await publish(tester, SessionStatus.running);
      await publish(tester, SessionStatus.error);
      await publish(tester, SessionStatus.idle);

      expect(spy.reloads, 0);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('a turn that ended while another chat was open does not reload on return', (
      tester,
    ) async {
      await pumpShell(tester, reloadAfterTurn: true);
      await startRun(tester);
      final data = workspaceOf(tester).dataController;

      await publish(tester, SessionStatus.running);
      data.selectSession(otherSessionId);
      await settle(tester);
      data.selectSession(sessionId);
      await publish(tester, SessionStatus.idle);

      expect(spy.reloads, 0);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('does nothing while the switch is off', (tester) async {
      await pumpShell(tester);
      await startRun(tester);

      await publish(tester, SessionStatus.running);
      await publish(tester, SessionStatus.idle);

      expect(spy.reloads, 0);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('does nothing when the app is not running', (tester) async {
      await pumpShell(tester, reloadAfterTurn: true);

      await publish(tester, SessionStatus.running);
      await publish(tester, SessionStatus.idle);

      expect(spy.reloads, 0);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('shortcuts', () {
    testWidgets('⌘R reloads and ⇧⌘R restarts the running app', (tester) async {
      await pumpShell(tester);
      await startRun(tester);

      await pressShortcut(tester, LogicalKeyboardKey.keyR);
      expect((spy.reloads, spy.restarts), (1, 0));

      await pressShortcut(tester, LogicalKeyboardKey.keyR, shift: true);
      expect((spy.reloads, spy.restarts), (1, 1));
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('they do nothing while the app is not running', (tester) async {
      await pumpShell(tester);

      await pressShortcut(tester, LogicalKeyboardKey.keyR);
      await pressShortcut(tester, LogicalKeyboardKey.keyR, shift: true);

      expect((spy.reloads, spy.restarts), (0, 0));
      expect(find.byType(SnackBar), findsNothing);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('title bar', () {
    testWidgets('the run button starts the selected device', (tester) async {
      await pumpShell(tester);
      final workspace = workspaceOf(tester);
      await until(tester, () => workspace.runController.state.selectedDeviceId != null);
      expect(find.byTooltip('Hot reload'), findsOneWidget);

      await tester.tap(find.byTooltip('Run'));
      await settle(tester);

      expect(spy.started, <String?>[workspace.runController.state.selectedDeviceId]);
      await until(tester, () => running(tester));
      expect(find.byTooltip('Stop the app'), findsOneWidget);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the device chip edits the run arguments and the run button starts with them', (
      tester,
    ) async {
      await pumpShell(tester);
      final workspace = workspaceOf(tester);
      await until(tester, () => workspace.runController.state.selectedDeviceId != null);

      final chip = find.descendant(
        of: find.byType(WorkspaceRunControls),
        matching: find.byType(RunDeviceChip),
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run arguments…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey<String>('run-arguments-flavor')), 'dev');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      await until(
        tester,
        () => workspace.runController.state.arguments == const RunArguments(flavor: 'dev'),
      );

      await tester.tap(find.byTooltip('Run'));
      await settle(tester);

      expect(spy.startedArguments, <RunArguments>[const RunArguments(flavor: 'dev')]);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the stop button stops the app', (tester) async {
      await pumpShell(tester);
      await startRun(tester);

      await tester.tap(find.byTooltip('Stop the app'));
      await until(tester, () => workspaceOf(tester).runController.state.run is RunStopped);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the run controls are not shown on the Settings screen', (tester) async {
      await pumpShell(tester);
      expect(find.byTooltip('Run'), findsOneWidget);

      workspaceOf(tester).dataController.openView(WorkspaceView.settings);
      await settle(tester);

      expect(find.byTooltip('Run'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });

    testWidgets('the run controls are hidden without a project', (tester) async {
      await pumpShell(tester);
      workspaceOf(tester).dataController.clearSelection();
      await settle(tester);

      expect(find.byTooltip('Run'), findsNothing);
      expect(find.byTooltip('Hot reload'), findsNothing);
      await disposeTestApp(tester, dependencies);
    });
  });

  group('@ from the run', () {
    testWidgets('the menu offers the picked widget and the last error', (tester) async {
      await pumpShell(tester);
      await startRun(tester);
      await reloadUntilError(tester);
      workspaceOf(tester).runController.setPicked(
        const PickedWidget(
          name: 'BookingCard',
          file: 'lib/src/feature/booking/widgets/booking_card.dart',
          line: 42,
          ancestors: <String>[],
        ),
      );
      await settle(tester);
      final chat = tester.state<ChatConfigWidgetState>(find.byType(ChatConfigWidget));

      await tester.enterText(find.byType(TextField), '@');
      await tester.pump();

      expect(find.text('From the run'), findsOneWidget);
      expect(find.text('Selected widget'), findsOneWidget);
      expect(find.text('Last error'), findsOneWidget);

      await tester.tap(find.text('Selected widget'));
      await tester.pump();
      expect(
        chat.textController.text,
        '@widget BookingCard (lib/src/feature/booking/widgets/booking_card.dart:42) ',
      );
      await disposeTestApp(tester, dependencies);
    });
  });
}

final DateTime _epoch = DateTime.utc(2026);
