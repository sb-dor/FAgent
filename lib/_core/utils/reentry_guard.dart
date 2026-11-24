/// A flag that is up while a synchronous [run] is in progress, down again afterwards even if it threw.
///
/// For code that changes something it listens to itself (a document edited by the controller that
/// watches the document): the listener checks [active] and ignores its own edit. It lives outside
/// controllers because a controller has no `finally`.
final class ReentryGuard {
  bool _active = false;

  /// Whether a [run] is in progress.
  bool get active => _active;

  /// Runs [body] with [active] up and returns its result; [active] is down again when it ends.
  T run<T>(T Function() body) {
    _active = true;
    try {
      return body();
    } finally {
      _active = false;
    }
  }
}
