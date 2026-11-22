import 'package:drift/drift.dart';
import 'package:flutter_code_agent/src/common/telemetry/error_outbox.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// An error whose details are hidden: the type, the type of the cause and the SQLite codes stay.
///
/// Use it for errors whose text can hold data (SQLite, drift, `FormatException`): the queue and
/// Sentry get the original type ([reportedType]) and no text.
final class HiddenDetailsError implements Exception, ReportedError {
  /// Hides the details of [original].
  HiddenDetailsError(Object original)
    : reportedType = original.runtimeType.toString(),
      _summary = _describe(original);

  @override
  final String reportedType;
  final String _summary;

  static String _describe(Object error) {
    final cause = error is DriftWrappedException ? error.cause : error;
    final buffer = StringBuffer(error.runtimeType.toString());
    if (error is DriftWrappedException && cause != null) {
      buffer.write(', cause ${cause.runtimeType}');
    }
    if (cause is SqliteException) {
      buffer.write(
        ', resultCode ${cause.resultCode}, extendedResultCode ${cause.extendedResultCode}',
      );
    }
    return buffer.toString();
  }

  @override
  String toString() => '$_summary (details hidden)';
}
