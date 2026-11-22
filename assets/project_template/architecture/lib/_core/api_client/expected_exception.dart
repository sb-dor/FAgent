/// A failure the feature expects as an answer, not a bug: the user can read it and act. The data
/// layer throws a subtype at the boundary; a controller sets its `error` state, and `ErrorUtil`
/// writes it to the log but keeps it out of the crash reporter (`isExpectedFailure` in
/// `lib/_core/telemetry/expected_failure.dart`).
abstract base class ExpectedException implements Exception {
  /// Creates the exception.
  const ExpectedException();
}

/// The server refused the request for a reason the user can fix: wrong credentials, a taken
/// email, a rejected value. `errorText` picks the text by [code], or shows [message] when the
/// server wrote one for the user.
final class RejectedException extends ExpectedException {
  /// Creates the exception.
  const RejectedException({required this.code, this.message});

  /// The server's reason, such as `wrong_password` or `email_taken`.
  final String code;

  /// A sentence for the user, in their language, when the server sent one.
  final String? message;

  @override
  String toString() => 'RejectedException($code)';
}
