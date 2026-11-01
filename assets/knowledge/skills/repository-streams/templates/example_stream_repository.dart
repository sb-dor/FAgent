import 'dart:async';

/// The three ways a repository may return a `Stream` so that it is always eventually closed.
final class ExampleStreamRepository {
  /// Creates the repository.
  const ExampleStreamRepository();

  /// Pattern 1, `onListen` / `onCancel`: lazy, and resources are freed when the listener cancels.
  ///
  /// The `cancelled` flag breaks the loop and stops `close()` from racing with `onListen`.
  Stream<int> countdown(int from, {Duration step = const Duration(seconds: 1)}) {
    final controller = StreamController<int>();
    var cancelled = false;
    controller
      ..onListen = () async {
        for (var value = from; value > 0 && !cancelled; value--) {
          controller.add(value);
          await Future<void>.delayed(step);
        }
        if (!controller.isClosed) await controller.close();
      }
      ..onCancel = () {
        cancelled = true;
        if (!controller.isClosed) controller.close();
      };
    return controller.stream;
  }

  /// Pattern 2, an `async` wrapper: the `finally` block guarantees `close()`.
  Stream<String> lines(Future<List<String>> Function() read) {
    final controller = StreamController<String>();
    Future<void>(() async {
      try {
        for (final line in await read()) {
          controller.add(line);
        }
      } on Object catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      } finally {
        await controller.close();
      }
    }).ignore();
    return controller.stream;
  }

  /// One-shot helpers: prefer the built-in constructors over a manual controller.
  Stream<int> single(int value) => Stream.value(value);

  /// A single asynchronous value, then done.
  Stream<int> singleLater(Future<int> value) => Stream.fromFuture(value);
}
