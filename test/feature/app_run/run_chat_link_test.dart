import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/session_status.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/fake_app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_view.dart';
import 'package:flutter_code_agent/src/feature/chat/widgets/chat_config_widget.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/controller/prompt_sending_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

/// The fake run that counts what the window asks it to do.
final class _SpyRunRepository implements IAppRunRepository {
  _SpyRunRepository() : _inner = FakeAppRunRepositoryImpl(step: const Duration(milliseconds: 1));

  final FakeAppRunRepositoryImpl _inner;
  final List<String> started = <String>[];
  int reloads = 0;
  int restarts = 0;

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
    required String deviceId,
    required BuildMode mode,
    required String target,
  }) {
    started.add(deviceId);
    return _inner.start(projectId, deviceId: deviceId, mode: mode, target: target);
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
  Future<void> dispose() => _inner.dispose();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Dependencies dependencies;
  late _SpyRunRepository spy;
  late int projectId;
  late int sessionId;
  late int otherSessionId;

  setUp(() {
    spy = _SpyRunRepository();
    dependencies = testDependencies(appRunRepository: spy);
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
    await until(tester, () => workspace.runController.state.selectedDeviceId != null);
    workspace.runActionsController.start(
      projectId,
      deviceId: workspace.runController.state.selectedDeviceId!,
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
