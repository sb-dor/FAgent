import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_code_agent/_core/database/database.steps.dart';
import 'package:flutter_code_agent/_core/database/tables/app_settings_table.dart';
import 'package:flutter_code_agent/_core/database/tables/chat_skill_states_table.dart';
import 'package:flutter_code_agent/_core/database/tables/code_view_state_table.dart';
import 'package:flutter_code_agent/_core/database/tables/custom_agents_table.dart';
import 'package:flutter_code_agent/_core/database/tables/mcp_servers_table.dart';
import 'package:flutter_code_agent/_core/database/tables/projects_table.dart';
import 'package:flutter_code_agent/_core/database/tables/run_configs_table.dart';
import 'package:flutter_code_agent/_core/database/tables/session_events_table.dart';
import 'package:flutter_code_agent/_core/database/tables/sessions_table.dart';
import 'package:flutter_code_agent/_core/database/tables/skill_states_table.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// {@template database}
/// The drift-managed database configuration
/// {@endtemplate}
@DriftDatabase(
  tables: [
    ProjectsTable,
    SessionsTable,
    SessionEventsTable,
    AppSettingsTable,
    SkillStatesTable,
    McpServersTable,
    McpServerStatesTable,
    RunConfigsTable,
    ChatSkillStatesTable,
    CustomAgentsTable,
    CodeViewStateTable,
  ],
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
  int get schemaVersion => 13;

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
      from5To6: (m, schema) async {
        await m.createTable(schema.mcpServers);
        await m.createTable(schema.mcpServerStates);
      },
      from6To7: (m, schema) async {
        await m.createTable(schema.runConfigs);
      },
      from7To8: (m, schema) async {
        await m.createTable(schema.chatSkillStates);
      },
      from8To9: (m, schema) async {
        await m.createTable(schema.customAgents);
      },
      from9To10: (m, schema) async {
        await m.addColumn(schema.runConfigs, schema.runConfigs.selectedConfig);
      },
      from10To11: (m, schema) async {
        await m.createTable(schema.codeViewState);
      },
      from11To12: (m, schema) async {
        await m.addColumn(schema.projects, schema.projects.rulesOffered);
      },
      from12To13: (m, schema) async {
        // The primary key gains app_folder, which SQLite can only do by rebuilding the table.
        // Existing rows become the project's root row.
        await m.alterTable(
          TableMigration(
            schema.runConfigs,
            newColumns: <GeneratedColumn<Object>>[
              schema.runConfigs.appFolder,
              schema.runConfigs.selectedApp,
            ],
          ),
        );
      },
    ),
    // SQLite ignores foreign keys (and ON DELETE CASCADE) unless enabled per connection.
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
