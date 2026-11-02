---
name: repository-streams
description: "Write Stream-returning repository methods that are always closed: onListen/onCancel, async wrapper, one-shot helpers."
when_to_use: "When a repository or service method returns Stream<T>, or when reviewing a StreamController for leaks."
version: "2.0"
---

# Stream-returning methods in repositories

A repository method that returns `Stream<T>` must guarantee the stream is eventually closed. Never
return a bare `StreamController.stream` without a close path: it leaks resources.

## Pattern 1: `onListen` / `onCancel` (lazy, resource-safe)

Code runs only when someone listens. Resources are released when the subscriber cancels.

```dart
Stream<R> fn() {
  final controller = StreamController<R>();
  controller
    ..onListen = () {
      // Start emitting values only when the stream is listened to.
      if (!controller.isClosed) controller.add(/* value of type R */);
    }
    ..onCancel = () {
      // Clean up resources when the stream is cancelled.
      if (!controller.isClosed) controller.close();
    };
  return controller.stream;
}
```

Add a mutex or boolean flag so `close()` is never called while `onListen` is still executing, and
so any loop inside `onListen` breaks when the stream is cancelled (see `countdown` in
`example_stream_repository.dart`).

## Pattern 2: `async Future` wrapper (simpler)

The whole emission logic is in an async closure; `finally` guarantees `close()`.

```dart
Stream<R> fn() {
  final controller = StreamController<R>();
  Future<void>(() async {
    try {
      // Your emission logic, e.g. a for(;;) loop.
      controller.add(r);
    } on Object catch (e, s) {
      controller.addError(e, s);
    } finally {
      controller.close();
    }
  }).ignore();
  return controller.stream;
}
```

The async body can also sit inside `onListen` instead of a standalone `Future`.

## One-shot helpers

Prefer the built-in constructors over a manual controller:

```dart
Stream.value(r)               // single value then done
Stream.fromFuture(future)     // single async value then done
Stream.fromFutures([f1, f2])  // several async values then done
```

## Rule

Every `Stream`-returning repository method uses one of the patterns above. A `StreamController`
with no guaranteed `close()` path is always wrong. Also cancel every subscription you create
(`StreamSubscription.cancel()` in `dispose`).

Template with all three patterns: `example_stream_repository.dart`.
