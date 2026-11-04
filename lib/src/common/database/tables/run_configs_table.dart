import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/tables/projects_table.dart';

/// What a project adds to every `flutter run`, and which launch configuration it runs. There is no
/// row for a project that never saved either.
@DataClassName('RunConfigRow')
class RunConfigsTable extends Table {
  @override
  String? get tableName => 'run_configs';

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{projectId};

  IntColumn get projectId =>
      integer().references(ProjectsTable, #id, onDelete: KeyAction.cascade)();

  /// The `--flavor`; `null` for none.
  TextColumn get flavor => text().nullable()();

  /// JSON list of the `--dart-define`s, each `KEY=VALUE`.
  TextColumn get dartDefines => text().withDefault(const Constant('[]'))();

  /// More arguments as the user typed them.
  TextColumn get extraArgs => text().withDefault(const Constant(''))();

  /// The name of the `.vscode/launch.json` configuration the Run button starts; `null` for Default
  /// (the arguments above).
  TextColumn get selectedConfig => text().nullable()();
}
