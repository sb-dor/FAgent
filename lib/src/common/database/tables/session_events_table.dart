import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/database/tables/sessions_table.dart';

/// Append-only journal of a chat: one row per raw ACP frame or app event.
///
/// The chat transcript is folded from these rows; nothing is merged in the
/// database. `seq` is assigned by the session's single writer in enqueue order.
@DataClassName('SessionEventRow')
class SessionEventsTable extends Table {
  @override
  String? get tableName => 'session_events';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get sessionId =>
      integer().references(SessionsTable, #id, onDelete: KeyAction.cascade)();

  /// Order of the event inside its session.
  IntColumn get seq => integer()();

  /// `user`, `agent` or `app`.
  TextColumn get origin => text()();

  /// `sessionUpdate` kind for agent updates, otherwise `prompt`,
  /// `permission_request`, `permission_resolution`, `system`, `turn_files`.
  TextColumn get kind => text()();

  /// Raw JSON of the event.
  TextColumn get payload => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => <Set<Column>>[
    <Column>{sessionId, seq},
  ];
}
