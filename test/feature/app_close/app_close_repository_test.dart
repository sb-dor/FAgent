import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_definition.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/chat_queue/queued_chats.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/agents/data/agent_probe.dart';
import 'package:flutter_code_agent/src/feature/agents/models/agent_probe_result.dart';
import 'package:flutter_code_agent/src/feature/app_close/data/app_close_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_probe.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_code_agent/src/feature/project_creation/data/project_creation_repository.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_devices_repository.dart';
import '../../support/scripted_app_run_repository.dart';
import '../../support/scripted_widget_picker_repository.dart';

/// Records when it is disposed, and whether the database was still open at that moment.
final class _RecordingRun extends ScriptedAppRunRepository {
  _RecordingRun(this.events, this.database);

  final List<String> events;
  final AppDatabase database;

  @override
  Future<void> dispose() async {
    events.add('run:start');
    // The database must still answer while the run is being stopped.
    await database.select(database.projectsTable).get();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    events.add('run:end');
    await super.dispose();
  }
}

final class _RecordingDevices extends MemoryDevicesRepository {
  _RecordingDevices(this.events, this.database);

  final List<String> events;
  final AppDatabase database;

  @override
  Future<void> dispose() async {
    events.add('devices:start');
    await database.select(database.projectsTable).get();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    events.add('devices:end');
    await super.dispose();
  }
}

/// Records when it is closed, and needs the database still open at that moment.
final class _RecordingAppMcpServer implements IAppMcpServer {
  _RecordingAppMcpServer(this.events, this.database);

  final List<String> events;
  final AppDatabase database;

  @override
  Future<void> start() async {}

  @override
  Uri? get url => null;

  @override
  int get toolCount => 0;

  @override
  Object? get startError => null;

  @override
  Future<void> close() async {
    events.add('mcp:close');
    await database.select(database.sessionsTable).get();
  }
}

/// Records when it is disposed, and needs the database still open at that moment.
final class _RecordingProbe implements IMcpProbe {
  _RecordingProbe(this.events, this.database);

  final List<String> events;
  final AppDatabase database;

  @override
  Future<McpProbeResult> probe(
    McpServer server, {
    Duration timeout = const Duration(seconds: 10),
  }) => throw UnimplementedError();

  @override
  Future<void> dispose() async {
    await database.select(database.projectsTable).get();
    events.add('probe:dispose');
  }
}

/// Records when it is disposed; reads the database first, so it must still be open.
final class _RecordingAgentProbe implements IAgentProbe {
  _RecordingAgentProbe(this.events, this.database);

  final List<String> events;
  final AppDatabase database;

  @override
  Future<AgentProbeResult> probe(AgentDefinition agent, {Duration? authStatusWait}) =>
      throw UnimplementedError();

  @override
  Future<void> dispose() async {
    await database.select(database.projectsTable).get();
    events.add('agent-probe:dispose');
  }
}

/// Records when it is disposed; throws when [error] is set.
final class _RecordingCreation implements IProjectCreationRepository {
  _RecordingCreation(this.events, {this.error});

  final List<String> events;
  final Error? error;

  @override
  Future<String> defaultParent() async => '/';

  @override
  Future<TargetProblem?> checkTarget(String parent, String name) async => null;

  @override
  Stream<CreationRun> create(NewProjectRequest request) => const Stream<CreationRun>.empty();

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    events.add('creation:dispose');
    if (error case final error?) throw error;
  }
}

void main() {
  late AppDatabase database;
  late List<String> events;
  late AppCloseRepositoryImpl repository;
  late _RecordingRun run;
  late _RecordingDevices devices;
  late _RecordingPicker picker;
  late AgentHub hub;
  late List<String> creationEvents;
  late _FixedQueuedChats queued;

  setUp(() {
    queued = _FixedQueuedChats();
    database = AppDatabase(NativeDatabase.memory());
    events = <String>[];
    creationEvents = <String>[];
    run = _RecordingRun(events, database);
    devices = _RecordingDevices(events, database);
    picker = _RecordingPicker(events);
    hub = AgentHub(
      database: database,
      environment: const ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'}),
    );
    repository = AppCloseRepositoryImpl(
      hub: hub,
      database: database,
      settings: AppSettingsRepositoryImpl(database: database),
      appRun: run,
      devices: devices,
      widgetPicker: picker,
      appMcpServer: _RecordingAppMcpServer(events, database),
      mcpProbe: _RecordingProbe(events, database),
      agentProbe: _RecordingAgentProbe(events, database),
      projectCreation: _RecordingCreation(creationEvents),
      queuedChats: queued,
    );
  });

  group('AppCloseRepositoryImpl.busyChats', () {
    test('no work and no queue is not busy', () async {
      expect(await repository.busyChats(), 0);
    });

    test('shutdown stops the queues before the agents', () async {
      queued.events = events;
      hub.notices.listen(null, onDone: () => events.add('hub:disposed'));

      await repository.shutdown();

      expect(events, containsAllInOrder(<String>['queues:dispose', 'hub:disposed']));
    });

    test('queued messages count as busy', () async {
      queued.sessionIds = <int>{3, 8};

      expect(await repository.busyChats(), 2);
    });
  });

  group('AppCloseRepositoryImpl.shutdown', () {
    test('stops the runs and the devices daemon together, before the database closes', () async {
      await repository.shutdown();

      expect(events, <String>[
        'picker:dispose',
        'run:start',
        'devices:start',
        'run:end',
        'devices:end',
        'mcp:close',
        'probe:dispose',
        'agent-probe:dispose',
      ]);
      // The database is closed once everything else is stopped.
      await expectLater(database.select(database.projectsTable).get(), throwsA(anything));
    });

    test('ends a widget pick before the runs stop', () async {
      final pick = picker.pick(1);

      await repository.shutdown();

      expect(await pick, isA<PickCancelled>());
      expect(events.take(2), <String>['picker:dispose', 'run:start']);
    });

    test('shutdown disposes the project creation', () async {
      await repository.shutdown();

      expect(creationEvents, <String>['creation:dispose']);
    });

    test('stops the agent probes before the database closes', () async {
      await repository.shutdown();

      // It reads the database when it is disposed, so the event means the database was open.
      expect(events, contains('agent-probe:dispose'));
    });

    test('stops the MCP probes before the database closes', () async {
      await repository.shutdown();

      // It reads the database when it is disposed, so the event means the database was open.
      expect(events, contains('probe:dispose'));
    });

    test('closes the app MCP server after the agents, before the database', () async {
      hub.notices.listen(null, onDone: () => events.add('hub:disposed'));

      await repository.shutdown();

      expect(events.sublist(events.length - 4), <String>[
        'hub:disposed',
        'mcp:close',
        'probe:dispose',
        'agent-probe:dispose',
      ]);
      await expectLater(database.select(database.projectsTable).get(), throwsA(anything));
    });

    test('stops following the agent list before the agents stop', () async {
      hub.notices.listen(null, onDone: () => events.add('hub:disposed'));
      repository = AppCloseRepositoryImpl(
        hub: hub,
        database: database,
        settings: AppSettingsRepositoryImpl(database: database),
        appRun: run,
        devices: devices,
        widgetPicker: picker,
        appMcpServer: _RecordingAppMcpServer(events, database),
        mcpProbe: _RecordingProbe(events, database),
        agentProbe: _RecordingAgentProbe(events, database),
        projectCreation: _RecordingCreation(creationEvents),
        stopAgentList: () async => events.add('agents:stop'),
        queuedChats: queued,
      );

      await repository.shutdown();

      expect(events, containsAllInOrder(<String>['agents:stop', 'hub:disposed']));
    });

    test(
      'a run that fails to stop does not keep the devices daemon or the database open',
      () async {
        final failing = _FailingRun();
        repository = AppCloseRepositoryImpl(
          hub: AgentHub(
            database: database,
            environment: const ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'}),
          ),
          database: database,
          settings: AppSettingsRepositoryImpl(database: database),
          appRun: failing,
          devices: devices,
          widgetPicker: picker,
          appMcpServer: _RecordingAppMcpServer(events, database),
          mcpProbe: _RecordingProbe(events, database),
          agentProbe: _RecordingAgentProbe(events, database),
          projectCreation: _RecordingCreation(
            creationEvents,
            error: StateError('the process would not die'),
          ),
          queuedChats: queued,
        );

        await repository.shutdown();

        expect(events, contains('devices:end'));
        expect(creationEvents, <String>['creation:dispose']);
        await expectLater(database.select(database.projectsTable).get(), throwsA(anything));
      },
    );
  });
}

/// The chats whose queue holds messages, as the test sets them; records when it is disposed
/// into [events] once a test sets them.
final class _FixedQueuedChats implements IQueuedChats {
  @override
  Set<int> sessionIds = const <int>{};

  List<String>? events;

  @override
  void discard(int sessionId) => sessionIds = <int>{...sessionIds}..remove(sessionId);

  @override
  void dispose() => events?.add('queues:dispose');
}

/// Records when it is disposed.
final class _RecordingPicker extends ScriptedWidgetPickerRepository {
  _RecordingPicker(this.events);

  final List<String> events;

  @override
  Future<void> dispose() async {
    events.add('picker:dispose');
    await super.dispose();
  }
}

final class _FailingRun extends ScriptedAppRunRepository {
  @override
  Future<void> dispose() async => throw StateError('the process would not die');
}
