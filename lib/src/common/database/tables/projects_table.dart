import 'package:drift/drift.dart';

/// Flutter projects opened in the app (the sidebar list).
@DataClassName('ProjectRow')
class ProjectsTable extends Table {
  @override
  String? get tableName => 'projects';

  IntColumn get id => integer().autoIncrement()();

  /// Absolute path to the project folder.
  TextColumn get path => text().unique()();

  TextColumn get name => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
}
