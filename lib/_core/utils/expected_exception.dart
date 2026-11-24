/// A failure that the user or the outside world causes and the UI shows: a taken name, a busy
/// chat, a file that changed on disk.
///
/// It is not a bug, so the controller observer logs it and does not report it as a crash.
abstract base class ExpectedException implements Exception {
  /// Creates the exception.
  const ExpectedException();
}
