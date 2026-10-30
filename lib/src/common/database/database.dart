import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_code_agent/src/common/database/database.steps.dart';
import 'package:flutter_code_agent/src/common/database/tables/app_settings_table.dart';
import 'package:flutter_code_agent/src/common/database/tables/projects_table.dart';
import 'package:flutter_code_agent/src/common/database/tables/session_events_table.dart';
import 'package:flutter_code_agent/src/common/database/tables/sessions_table.dart';
import 'package:flutter_code_agent/src/common/database/tables/skill_states_table.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// {@template database}
/// The drift-managed database configuration
/// {@endtemplate}
@DriftDatabase(
  tables: [ProjectsTable, SessionsTable, SessionEventsTable, AppSettingsTable, SkillStatesTable],
)
class AppDatabase extends _$AppDatabase {
  /// {@macro database}
  AppDatabase(super.e);

  /// {@macro database}
  ///
  /// Stored in Application Support: drift's default on desktop is the user's Documents folder.
  AppDatabase.defaults({required String name})
    : super(
        driftDatabase(
          name: name,
          native: const DriftNativeOptions(
            shareAcrossIsolates: true,
            databaseDirectory: getApplicationSupportDirectory,
          ),
        ),
      );

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.addColumn(schema.projects, schema.projects.isFlutter);
        await m.addColumn(schema.projects, schema.projects.trustedAt);
        await m.createTable(schema.sessions);
        await m.createTable(schema.sessionEvents);
      },
      from2To3: (m, schema) async {
        await m.addColumn(schema.sessions, schema.sessions.bypassAllowedAt);
      },
      from3To4: (m, schema) async {
        await m.createTable(schema.appSettings);
      },
      from4To5: (m, schema) async {
        await m.createTable(schema.skillStates);
      },
    ),
    // SQLite ignores foreign keys (and ON DELETE CASCADE) unless enabled per connection.
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
