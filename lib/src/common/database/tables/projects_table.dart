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

  /// The folder has a `pubspec.yaml` depending on `flutter`. Re-checked when
  /// the project is opened.
  BoolColumn get isFlutter => boolean().withDefault(const Constant(false))();

  /// When the user allowed agents to run this folder's settings and hooks.
  /// No agent session starts in the project while this is `null`.
  DateTimeColumn get trustedAt => dateTime().nullable()();
}
