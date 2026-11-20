import 'package:drift/drift.dart';

@DataClassName('Log')
class LogTbl extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get time => integer().withDefault(currentDateAndTime.unixepoch)();
  IntColumn get level => integer()();
  TextColumn get message => text()();
  TextColumn get stack => text().nullable()();
}

class LogPrefixTbl extends Table {
  TextColumn get prefix => text()();
  IntColumn get logId => integer().references(LogTbl, #id)();
  TextColumn get word => text()();
  IntColumn get len => integer()();

  @override
  Set<Column> get primaryKey => {prefix, logId, word};
}
