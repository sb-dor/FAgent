import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:flutter_code_agent/_core/telemetry/error_outbox.dart';
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
    final cause = switch (error) {
      DriftWrappedException(:final cause) => cause,
      DriftRemoteException(:final remoteCause) => remoteCause,
      _ => error,
    };
    final buffer = StringBuffer(error.runtimeType.toString());
    if (!identical(cause, error) && cause != null) {
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

/// An opt-in `ErrorReporter.hideDetails` (the default sends the full text): the errors whose text can hold the app's data go to
/// the queue as a [HiddenDetailsError]. `SqliteException` prints the statement and its parameters,
/// drift's [DriftWrappedException] and [DriftRemoteException] print their cause, and
/// [FormatException] prints a slice of the input it failed on. Any other error is returned as is.
Object hideDataDetails(Object error) => switch (error) {
  SqliteException() ||
  DriftWrappedException() ||
  DriftRemoteException() ||
  FormatException() => HiddenDetailsError(error),
  _ => error,
};
