import 'package:drift/drift.dart';

/// The ACP agents the user added; the built-in ones live in code.
@DataClassName('CustomAgentRow')
class CustomAgentsTable extends Table {
  @override
  String? get tableName => 'custom_agents';

  /// The agent's id is `custom:<id>`.
  IntColumn get id => integer().autoIncrement()();

  /// The name the UI shows.
  TextColumn get name => text()();

  /// Bare name looked up on the shell `PATH`, or an absolute path.
  TextColumn get executable => text()();

  /// JSON list of strings.
  TextColumn get arguments => text().withDefault(const Constant('[]'))();

  /// JSON map of strings.
  TextColumn get environment => text().withDefault(const Constant('{}'))();

  /// `RulesChannel.name`.
  TextColumn get rulesChannel => text().withDefault(const Constant('firstMessage'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
