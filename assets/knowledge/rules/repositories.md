---
name: repositories
description: "Repository interface plus Impl, Stream-returning methods that always close, and safe Drift schema changes."
---

# Repositories

## Rules

- `abstract interface class IFooRepository` plus `final class FooRepositoryImpl implements ...`.
  Services (API client, database, file system, processes) come through the constructor.
- App-global scope values (selected store, organisation) are read by the repository, not passed
  through widgets and controllers. Only per-screen filters and ids travel through `load(...)`.
- A `Stream`-returning method must always close its stream: `onListen`/`onCancel`, or an `async`
  wrapper with `close()` in `finally`. For one value use `Stream.value`/`Stream.fromFuture`. A
  `StreamController` without a guaranteed `close()` is a bug.
- Create-vs-update is decided in the repository, not in the controller or widget.

## Stream-returning methods in repositories

A repository method that returns `Stream<T>` must guarantee the stream is eventually closed. Never
return a bare `StreamController.stream` without a close path: it leaks resources.

### Pattern 1: `onListen` / `onCancel` (lazy, resource-safe)

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

### Pattern 2: `async Future` wrapper (simpler)

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

### One-shot helpers

Prefer the built-in constructors over a manual controller:

```dart
Stream.value(r)               // single value then done
Stream.fromFuture(future)     // single async value then done
Stream.fromFutures([f1, f2])  // several async values then done
```

### Rule

Every `Stream`-returning repository method uses one of the patterns above. A `StreamController`
with no guaranteed `close()` path is always wrong. Also cancel every subscription you create
(`StreamSubscription.cancel()` in `dispose`).

Template with all three patterns: `example_stream_repository.dart`.

## Drift migration

Only add a local table when the feature really needs persistence. Never edit `*.g.dart` by hand.

### Steps

1. Put the table class in `lib/src/common/database/tables/<name>_table.dart`.
2. Add the table to `@DriftDatabase(tables: [...])` in `lib/src/common/database/database.dart`.
3. Bump `schemaVersion` by one.
4. Dump the new schema and regenerate the step helper:
   `dart run drift_dev schema dump lib/src/common/database/database.dart drift_schemas/` then
   `dart run drift_dev schema steps drift_schemas/ lib/src/common/database/database.steps.dart`.
5. Add the new step to the `stepByStep(...)` call in `migration`, for example
   `from1To2: (migrator, schema) async => migrator.create(schema.exampleTable)`.
6. Run `dart run build_runner build --delete-conflicting-outputs`.
7. Cover the upgrade with a migration test that opens the old schema and checks the data survives.

### Checks

- `onCreate` still calls `createAll()`; `onUpgrade` uses the generated `stepByStep`.
- A column added to an existing table has a default or is nullable.
- Repositories get the database through the constructor; widgets never touch it.

## Examples

Whole files, one per block; put each where the layout above says and adjust the imports.

### `example_stream_repository.dart`

```dart
// file: example_stream_repository.dart
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
```
