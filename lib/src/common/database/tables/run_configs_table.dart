import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/tables/projects_table.dart';

/// What a project adds to every `flutter run` of each of its apps, and which launch configuration
/// and app it runs. There is no row for an app that never saved arguments; the root row (an empty
/// [appFolder]) also holds what is stored once per project.
@DataClassName('RunConfigRow')
class RunConfigsTable extends Table {
  @override
  String? get tableName => 'run_configs';

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{projectId, appFolder};

  IntColumn get projectId =>
      integer().references(ProjectsTable, #id, onDelete: KeyAction.cascade)();

  /// The app the arguments are for, relative to the project (`apps/desktop`); `''` for the
  /// project root.
  TextColumn get appFolder => text().withDefault(const Constant(''))();

  /// The `--flavor`; `null` for none.
  TextColumn get flavor => text().nullable()();

  /// JSON list of the `--dart-define`s, each `KEY=VALUE`.
  TextColumn get dartDefines => text().withDefault(const Constant('[]'))();

  /// More arguments as the user typed them.
  TextColumn get extraArgs => text().withDefault(const Constant(''))();

  /// The name of the `.vscode/launch.json` configuration the Run button starts; `null` for Default
  /// (the arguments above). Read from the root row only.
  TextColumn get selectedConfig => text().nullable()();

  /// The [appFolder] of the app a monorepo runs; `null` for none chosen. Read from the root row
  /// only.
  TextColumn get selectedApp => text().nullable()();
}
