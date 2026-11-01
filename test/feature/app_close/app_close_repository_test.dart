import 'package:drift/native.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/app_close/data/app_close_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_devices_repository.dart';
import '../../support/scripted_app_run_repository.dart';

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

void main() {
  late AppDatabase database;
  late List<String> events;
  late AppCloseRepositoryImpl repository;
  late _RecordingRun run;
  late _RecordingDevices devices;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    events = <String>[];
    run = _RecordingRun(events, database);
    devices = _RecordingDevices(events, database);
    repository = AppCloseRepositoryImpl(
      hub: AgentHub(
        database: database,
        environment: const ShellEnvironment(<String, String>{'PATH': '/usr/bin:/bin'}),
      ),
      database: database,
      settings: AppSettingsRepositoryImpl(database: database),
      appRun: run,
      devices: devices,
    );
  });

  group('AppCloseRepositoryImpl.shutdown', () {
    test('stops the runs and the devices daemon together, before the database closes', () async {
      await repository.shutdown();

      expect(events, <String>['run:start', 'devices:start', 'run:end', 'devices:end']);
      // The database is closed once everything else is stopped.
      await expectLater(database.select(database.projectsTable).get(), throwsA(anything));
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
        );

        await repository.shutdown();

        expect(events, contains('devices:end'));
        await expectLater(database.select(database.projectsTable).get(), throwsA(anything));
      },
    );
  });
}

final class _FailingRun extends ScriptedAppRunRepository {
  @override
  Future<void> dispose() async => throw StateError('the process would not die');
}
