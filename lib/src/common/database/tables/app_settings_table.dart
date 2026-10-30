import 'package:drift/drift.dart';

/// Key-value store for window-level settings; values are JSON.
@DataClassName('AppSettingRow')
class AppSettingsTable extends Table {
  @override
  String? get tableName => 'app_settings';

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};

  /// Setting group, e.g. `app`.
  TextColumn get key => text()();

  /// JSON document.
  TextColumn get value => text()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
