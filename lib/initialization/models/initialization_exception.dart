/// A startup step that failed; [step] is its name (for the log), [cause] the original error.
final class InitializationException implements Exception {
  /// Creates the exception.
  const InitializationException(this.step, this.cause);

  /// The step that failed.
  final String step;

  /// What the step threw.
  final Object cause;

  @override
  String toString() => 'Initialization failed at step "$step": $cause';
}
