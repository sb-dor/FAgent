import 'package:drift/drift.dart' show DriftWrappedException;
import 'package:flutter_code_agent/src/common/telemetry/error_outbox.dart';
import 'package:flutter_code_agent/src/common/telemetry/hidden_details_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

void main() {
  test('keeps the original type and drops the text', () {
    final error = HiddenDetailsError(const FormatException('bad input anna@example.com'));

    expect(error.reportedType, 'FormatException');
    expect(errorTypeName(error), 'FormatException');
    expect(error.toString(), 'FormatException (details hidden)');
    expect(error.toString(), isNot(contains('anna')));
  });

  test('keeps the cause type and the SQLite codes of a wrapped error', () {
    final cause = SqliteException(
      extendedResultCode: 2067,
      message: 'UNIQUE constraint failed: users.email',
    );
    final error = HiddenDetailsError(
      DriftWrappedException(message: 'insert into users', cause: cause, trace: null),
    );

    expect(error.reportedType, 'DriftWrappedException');
    expect(error.toString(), contains('cause SqliteException'));
    expect(error.toString(), contains('extendedResultCode 2067'));
    expect(error.toString(), isNot(contains('users')));
  });

  test('hideDataDetails hides only errors whose text holds data', () {
    final state = StateError('kept');
    final hidden = HiddenDetailsError(const FormatException('x'));

    expect(hideDataDetails(state), same(state));
    expect(hideDataDetails(hidden), same(hidden));
    expect(hideDataDetails(const FormatException('input')), isA<HiddenDetailsError>());
    expect(
      hideDataDetails(SqliteException(extendedResultCode: 1, message: 'no such table: users')),
      isA<HiddenDetailsError>(),
    );
  });
}
