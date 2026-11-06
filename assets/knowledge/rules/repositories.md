---
name: repositories
description: "Stateless repositories: interface plus Impl, no StreamController fields, Stream-returning methods that always close, decoding response bodies as UTF-8, and safe Drift schema changes."
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
- A repository holds no state: no `StreamController`, subscription, cache or connection in its
  fields, and so no `dispose`. A stream it returns comes from the source (a drift `watch()`,
  Firestore `snapshots()`) or from a controller the method creates and closes itself. See "No state
  in a repository".
- Create-vs-update is decided in the repository, not in the controller or widget.
- Catch an error only to handle it or to pass it on with `rethrow`. A `throw` inside a `catch` is
  only for turning the server's code into the app's own exception at the boundary (an
  `APIClientException$Client` with `{"code": "email_taken"}` into `RejectedException`), with the
  original stack trace. See "Errors".
- A failure the user can act on is thrown at the boundary as a subtype of `ExpectedException`;
  one that code above the data layer handles in its own way gets its own type, in a sealed
  family. A backend code the provider does not know is rethrown. See "A type for each failure the
  app acts on".
- Failure is thrown, never returned: no `Result`, `Either` or `DataOrException`. `return null`
  from a `catch` and `.ignore()` on a future are swallows. See "Errors".
- An operation the user can cancel owns one `Disposer` and takes a `CancellationToken`. See
  "Cancelling a multi-step operation".
- Local data goes to SQLite (drift) or, for a few small settings, `shared_preferences`; never to
  `hive`, `isar` or `get_storage`. See "Local storage".
- Text and JSON from the network are decoded from the bytes as UTF-8: `ApiClient` does it for JSON;
  code that reads `package:http` directly uses `utf8.decode(response.bodyBytes)`, not
  `Response.body`. See "Decoding response bodies".
- Every method of a repository (and of its data providers) is asynchronous, `Future` or `Stream`,
  even when the implementation is synchronous today; the next implementation then changes nothing
  above it. See "Data providers" in `docs/rules/architecture.md`.

## Errors

- **Do not catch what you cannot handle.** An error a repository cannot do anything about goes up
  to the controller, whose `handle` reports it to the observer: no `try`/`catch` at all, or a
  `catch` that does its part (closing a resource, logging) and then `rethrow`s.
- **`rethrow`, not `throw error`.** `rethrow` keeps the original stack trace; `throw e` inside a
  `catch` starts a new one at that line, and the place the error came from is lost.
- **Translate at the boundary, and only there.** The project's `ApiClient` already turns every
  transport failure into an `APIClientException` (see "HTTP clients" in
  `docs/rules/dependencies.md`); those pass on as they are, and nothing re-wraps them into generic
  app exceptions. The data provider is the one place that reads the server's codes: on an
  `APIClientException$Client` (a 4xx), or an `APIClientException$Authorization` where the code is
  an answer (a 401 with `invalid_credentials` on sign-in, a request sent without a token), it
  reads `error.data` with a map pattern and throws the app's exception. A failure the user can
  read and act on (a wrong password, a used coupon) is thrown as a subtype of `ExpectedException`
  (`app_exception.dart` in `docs/rules/controllers.md`): the controller shows it and does not
  report it. An unknown code, or no body, is rethrown: it keeps its own type and is reported. A
  local query that found no row throws the feature's `NotFoundException`. Keep the original stack
  trace with `Error.throwWithStackTrace`:

```dart
try {
  await _client.post('/users', body: <String, Object?>{'email': email});
} on APIClientException$Client catch (error, stackTrace) {
  if (error.data case {'code': 'email_taken'}) {
    Error.throwWithStackTrace(const RejectedException(code: 'email_taken'), stackTrace);
  }
  rethrow; // another code, another 4xx, no body: reported as it is
}
```

- **Throw; do not return a `Result`.** Repositories and data providers report a failure by
  throwing, never by returning `Result`, `Either` (`dartz`, `fpdart`) or a `DataOrException`
  union. The SDK and every package throw, so a result type adds a second mechanism next to the
  first: every boundary catches and wraps, every caller unwraps, and the controller still has to
  catch what nobody wrapped. In Dart the stack trace is not part of the exception, so a union that
  holds only the error loses it, and an error thrown again from it points at the line that
  unwrapped it. A sealed `Result` checked by an exhaustive `switch` does work in Dart 3; these rules
  still keep one mechanism: exceptions, caught in the controller's action, which sets the `error`
  state and rethrows what is not an `ExpectedException` to `handle` (see "Expected and unexpected
  errors" in `docs/rules/controllers.md`).
- **Never swallow.** An empty `catch`, a `catch` that returns `null`, `[]` or another default, and
  `.ignore()` on a future all hide the failure from the controller, the user and the crash report.
  Return a default only when it is the answer (an optional file that is missing), and say so in a
  comment.
- **`unawaited` is not `.ignore()`.** `unawaited(f)` only marks not waiting as deliberate, for
  the reader and for the `unawaited_futures` lint in a project that enables it (the project
  template leaves it off, so nothing reports a future that is neither awaited nor wrapped). It
  changes nothing at run time: when `f` fails, its error is uncaught and goes to the zone's
  handler (`PlatformDispatcher.instance.onError` in the app), where it is still reported.
  `f.ignore()` marks the error as handled and drops it. Use `.ignore()` only on a future that
  cannot fail with anything worth knowing: a controller method, whose `handle` reports its own
  errors, or a body that catches everything itself. A fire-and-forget write whose failure matters
  (a cache write) is awaited, or gets a `catchError` that logs it. Checked: inside
  `runZonedGuarded`, a failing `unawaited` future reaches the handler and an `.ignore()`d one does
  not.
- **Context beside the error, never secrets.** What helps to find the cause (the path, the status
  code, the backend's error code) goes into the exception's fields and `toString()`, or into the
  report next to the error and its stack trace. Do not rebuild the trace to carry it
  (`StackTrace.fromString('$trace\nHeaders: ...')`). Headers, tokens, passwords and request bodies
  with personal data never go into an exception, its message or a trace: exceptions end up in logs
  and crash reports (see "Rules" in `docs/rules/security.md`).
- **Catch what you mean.** `on APIClientException$Client`, `on FormatException`, not a bare
  `catch` around a whole method; the controller's `handle` is the one place that catches everything.
- **No `try` / `finally` without an `on Object catch`.** Write the catch, even when it only logs
  and `rethrow`s: `try { ... } on Object catch (error, stackTrace) { ...; rethrow; } finally { ... }`.
  A bare `try` / `finally` hides what happens to the error, and the `finally` decides it silently:
  a `return` in `finally` drops the error, a `throw` (or a failing cleanup call) in `finally`
  replaces it with its own. Keep `finally` to cleanup that cannot throw, and never `return` from
  it.

### A type for each failure the app acts on

When code above the data layer does something particular for one failure (offers a top-up, clears
the coupon field, sends the user to sign in), the data provider that sees the failure throws a type
named after it: `InsufficientFundsException`, `CouponAlreadyUsedException`, `NotFoundException`
for a query that found no row. Nothing above the provider then compares strings or status codes.

- A failure that only needs a message stays generic: for a code the provider knows, a
  `RejectedException` (an `ExpectedException`) with the backend's code and message, which
  `errorText` turns into a sentence (see "Error messages" in `docs/rules/localization.md`). A
  failure nobody can act on (a 500, a failed parse, an unknown code) passes on unchanged and
  untyped, and a lost connection as the client's `APIClientException$Network`: none is an
  `ExpectedException`, so all are reported.
- A feature's types form a `sealed class ... extends ExpectedException` with `final class`
  subtypes and `const` constructors: a `switch` over them is exhaustive, and a new type is a
  compile error wherever it is not handled. They are `Exception`s, not `Error`s: an `Error` means
  a bug in the code. (`ExpectedException` is a `base` class: a subtype `extends` it and is itself
  `base`, `final` or `sealed`.)
- They carry what the app needs (the coupon that was used), never a transport type
  (`APIClientException`, `APIClientResponse`) and nothing secret.
- The provider maps the backend's code with `Error.throwWithStackTrace`, so the report still points
  at the request, and `rethrow`s every code it does not know: an unknown code is never swallowed
  and never guessed. A map pattern matches only when every key it names is there: read an
  optional `message` in a pattern of its own, or `{'code': ..., 'message': ...}` misses a body
  without a message. See `payments_data_provider.dart` in Examples, and "Testing the data layer"
  in `docs/rules/testing.md` for its tests.

## Releasing resources

A `dispose` that releases several things (a stream subscription, a socket, a process, a database)
must release all of them even when one fails, and must not hang on one that never answers:

- Each step gets its own `try` / `on Object catch`, so a failing step does not skip the rest.
- An asynchronous step gets a timeout (`.timeout(...)`): a socket that never closes must not keep
  the app from shutting down.
- A failure goes to a callback or the log, never into silence.
- Steps that do not depend on each other may run together (`Future.wait`, safe here because each
  step catches its own error; see "Waiting for several futures" in `docs/rules/dart.md`); those
  that must run in order run one after another, or through one `Mutex` (`control`'s
  `Mutex().synchronize`) when several disposers share them.
- An object that owns native memory (a `ui.Image`, a `Picture`, the image or handle of an FFI
  package) is disposed right after use, in the `finally` of the `try` that uses it. Do not rely on
  a finalizer the package attaches: the `Finalizer` doc makes "no promises" that its callback is
  ever called, and on the web a package may have none.

```dart
// file: dispose_all.dart
import 'dart:async';
import 'dart:developer' as developer;

/// Runs every cleanup step, in order, even when some fail: each one gets [timeout], and a failure
/// goes to [onError] instead of stopping the rest.
Future<void> disposeAll(
  Map<String, FutureOr<void> Function()> steps, {
  Duration timeout = const Duration(seconds: 5),
  void Function(String step, Object error, StackTrace stackTrace)? onError,
}) async {
  for (final MapEntry(key: name, value: step) in steps.entries) {
    try {
      await Future<void>.sync(step).timeout(timeout);
    } on Object catch (error, stackTrace) {
      (onError ?? _log)(name, error, stackTrace);
    }
  }
}

void _log(String step, Object error, StackTrace stackTrace) => developer.log(
  'Dispose step "$step" failed',
  error: error,
  stackTrace: stackTrace,
  name: 'dispose',
);
```

```dart
Future<void> dispose() => disposeAll({
  'Cancel the subscription': () => _subscription?.cancel(),
  'Close the socket': () => _socket.close(),
  'Kill the agent process': () => _process.kill(),
});
```

### Release in reverse order

What was created first is released last: a subscription to a socket is cancelled before the socket
closes, the socket closes before the client it came from. Listing the steps by hand in a
`dispose` drifts from the order of creation, and a resource added later is easily forgotten.
`Disposer` (`disposer.dart`) keeps the two together: register each cleanup step with `defer` right
after creating the resource, and `dispose` runs them last-first, each one even when another fails
or hangs.

```dart
final class ChatSession {
  ChatSession(this._client) {
    _disposer.defer('Close the client', _client.close);
  }

  final HttpClient _client;
  final Disposer _disposer = Disposer();

  Future<void> connect(Uri uri) async {
    final socket = await WebSocket.connect(uri.toString());
    _disposer.defer('Close the socket', socket.close);
    final subscription = socket.listen(_onMessage);
    _disposer.defer('Cancel the subscription', subscription.cancel);
  }

  Future<void> dispose() => _disposer.dispose();
}
```

In a `State`, `dispose()` is synchronous: dispose the controllers and notifiers there directly,
and start the asynchronous steps without awaiting them (`unawaited(_disposer.dispose())`). A
mixin on `State` that keeps a list of cleanup functions must run it backwards, report each
failure with its stack trace, and type the steps (`FutureOr<void> Function()`), not `Function`.

A chain of closures (`dispose = () { try { fn(); } finally { previous(); } }`, or a mixin built on
it) gets the order right but loses errors: when two steps throw, the error thrown in the later
`finally` replaces the first, which is never reported. It also has no timeout, and a mixin that
ignores `defer` after disposal leaks what an `await` created too late. The chain lives in a
variable that every registration replaces, so it cannot be handed to anyone: `addListener(dispose)`
stores the chain as it was at that moment, without the steps registered after it, and
`removeListener(dispose)` passes a different closure and removes nothing (checked). `Disposer`
reports every failure, times out a hanging step, and runs a late `defer` at once; `disposer.dispose`
is a method tear-off, equal every time it is read (checked), so it is safe to pass and to remove.

```dart
// file: disposer.dart
import 'dart:async';
import 'dart:developer' as developer;

/// Collects cleanup steps as resources are created and runs them in reverse order on [dispose]:
/// what was created first is released last.
///
/// Every step runs even when another fails or hangs: each one gets [timeout], and a failure goes
/// to `onError` (the log by default) instead of stopping the rest.
final class Disposer {
  Disposer({
    this.timeout = const Duration(seconds: 5),
    void Function(String step, Object error, StackTrace stackTrace)? onError,
  }) : _onError = onError ?? _log;

  /// How long one step may take.
  final Duration timeout;

  final void Function(String step, Object error, StackTrace stackTrace) _onError;
  final List<(String, FutureOr<void> Function())> _steps = <(String, FutureOr<void> Function())>[];
  Future<void>? _disposed;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed != null;

  /// Registers [step], called [name] in error reports, to run on [dispose].
  ///
  /// Call it right after creating the resource. After [dispose] the step runs at once, so a
  /// resource created late (when an `await` finished after the owner was disposed) is not leaked.
  void defer(String name, FutureOr<void> Function() step) {
    if (_disposed != null) {
      unawaited(_run(name, step));
      return;
    }
    _steps.add((name, step));
  }

  /// Runs the steps, the last registered first. Calling it again returns the same future.
  Future<void> dispose() => _disposed ??= _disposeAll();

  Future<void> _disposeAll() async {
    final steps = _steps.reversed.toList(growable: false);
    _steps.clear();
    for (final (name, step) in steps) {
      await _run(name, step);
    }
  }

  Future<void> _run(String name, FutureOr<void> Function() step) async {
    try {
      await Future<void>.sync(step).timeout(timeout);
    } on Object catch (error, stackTrace) {
      _onError(name, error, stackTrace);
    }
  }

  static void _log(String step, Object error, StackTrace stackTrace) => developer.log(
    'Dispose step "$step" failed',
    error: error,
    stackTrace: stackTrace,
    name: 'dispose',
  );
}
```

### Cancelling a multi-step operation

An operation the user can cancel (an import, a sync, an upload in steps) owns one `Disposer` and
takes a `CancellationToken` from its caller (`cancellable_import.dart` below):

- Each undo step is registered with `defer` right after its resource exists, as above.
- A cancel disposes at once (`token.whenCancelled.then(...)`): a step waiting on an open resource
  (a stream of rows, a socket) then ends instead of running to its end. A resource that finishes
  opening after the cancel is released by the late `defer`, which runs at once.
- After every `await`, check `token.isCancelled` and return.
- An error that follows a cancel comes from the released resources: the operation returns as
  cancelled and reports no failure.
- A step that only undoes a failure (a transaction's `rollback`) checks a flag it closes over,
  set once the commit succeeded: disposing after success runs every other step and never rolls
  back a committed transaction.
- The point of no return is explicit: check the token right before the commit and set a flag
  there; a cancel after it changes nothing, so it cannot roll back a commit in progress.
- The token is a `Completer<void>` in plain Dart, not a `ChangeNotifier`: nothing below the
  controllers imports Flutter, there is no listener to remove, and a second `cancel()` does nothing.

Checked with tests: on success the rows are committed, nothing is rolled back and the source is
closed; a cancel while rows arrive rolls back and closes the source once, even when cancelled
twice; a cancel during `connect` closes the late source at once and never begins a transaction; a
cancel during the commit changes nothing; a failing insert rolls back and the error reaches the
caller.

```dart
// file: cancellable_import.dart
import 'dart:async';

import 'disposer.dart';

/// Asks a running operation to stop. The caller creates it, passes it in and keeps it to call
/// [cancel].
final class CancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called, and never otherwise.
  Future<void> get whenCancelled => _cancelled.future;

  /// Asks the operation to stop. Calling it again does nothing.
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// The server the rows come from.
abstract interface class IImportSource {
  /// The rows to import. Ends when there are no more, or when the source is closed.
  Stream<Map<String, Object?>> rows();

  Future<void> close();
}

/// The local transaction the rows are written in.
abstract interface class IImportTransaction {
  Future<void> insert(Map<String, Object?> row);

  Future<void> commit();

  Future<void> rollback();
}

/// Imports every row of the source in one transaction.
///
/// Completes with `true` when the rows were committed and with `false` when [token] cancelled the
/// import before the commit started. Whatever happens, what was opened is released, last first.
Future<bool> importRows({
  required Future<IImportSource> Function() connect,
  required Future<IImportTransaction> Function() begin,
  required CancellationToken token,
}) async {
  final disposer = Disposer();
  var committing = false;
  // A cancel releases what is open at once: a step waiting on it (the rows) ends.
  unawaited(
    token.whenCancelled.then((_) {
      if (!committing) return disposer.dispose();
    }),
  );
  try {
    final source = await connect();
    // Even when the cancel came during `connect`: a late `defer` runs at once.
    disposer.defer('Close the source', source.close);
    if (token.isCancelled) return false;

    final transaction = await begin();
    var committed = false;
    // Only for a failure or a cancel: a committed transaction is not rolled back.
    disposer.defer('Roll back', () {
      if (!committed) return transaction.rollback();
    });
    if (token.isCancelled) return false;

    await for (final row in source.rows()) {
      if (token.isCancelled) return false;
      await transaction.insert(row);
    }
    if (token.isCancelled) return false;

    // From here on a cancel changes nothing: the commit decides.
    committing = true;
    await transaction.commit();
    committed = true;
    return true;
  } on Object {
    // After a cancel, an error comes from the released resources: cancelled, not failed.
    if (token.isCancelled && !committing) return false;
    rethrow;
  } finally {
    // Never throws: every step reports its own failure.
    await disposer.dispose();
  }
}
```

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

### No state in a repository

A `StreamController` kept in a repository's field is state, exactly like a mutable list or an
offset in a field: the repository stops being a way to reach a source and becomes an owner of
data with a lifetime.

- What it holds depends on who used it before: a second screen, a test that reuses the instance or
  a signed-out user gets the previous events or a closed controller.
- It needs a `dispose`, and nobody knows when to call it, since several controllers use one
  repository.
- Controllers that sync through it race: two of them write, both listen, and the order of the
  events decides which state wins.

So data that changes is owned by the store (the database, the server) or by a controller, never
by a repository:

- **Data in a database**: the repository returns the database's own stream (`select(...).watch()`),
  which every listener gets fresh and which closes when they cancel.
- **App state that several features read** (settings, the session): an app-wide controller in
  `Dependencies` owns it and publishes it; a repository only loads and saves it.
- **A `StreamController` the repository must push to** (a shared event source): create it outside,
  with its owner's lifetime, and pass it in through the constructor.

### Choosing a transport

- **HTTP requests** for almost everything: one action, one answer, retried when it is safe to repeat
  (see "HTTP middleware" in `docs/rules/dependencies.md`).
- **Polling or long polling** when updates are rare and a few seconds of delay is fine.
- **SSE** when the server pushes updates (a feed, a status, a build log): one long HTTP response
  from the server, and plain HTTP requests, with their answers as the acknowledgement, from the
  client.
- **WebSocket** when both sides talk often and fast (a chat with typing indicators, a game, a
  shared editor). It needs the most: ids for calls, a heartbeat, reconnection and resync (below),
  and a server that keeps connections.

A slow operation (an export, a report) does not hold a request open: the server answers at once
with an operation id, and the app polls it or receives the result over SSE.

### Long-lived connections (WebSocket, SSE)

A repository method may open a connection and return its events as a stream, as long as the
stream owns the connection: it connects on `listen`, reconnects while someone listens, and
disconnects on `cancel`. Whoever listens owns its lifetime. `story_repository.dart` (in Examples)
does this with a `reconnecting` helper:

- It waits longer after each failure (1 s, 2 s, 4 s, up to 30 s) and starts again from 1 s after an
  event, so a server that is down is not hammered once a second.
- Errors reach the listener, which can show them, and the stream goes on.
- `onReconnected` runs after every reconnection: fetch what was missed while the connection was
  down (the messages after the last id in the database), or the app silently loses them.
- It reads the token on every connection, since it may have been refreshed since the last one.
- A cancelled stream leaves no timer and no open connection behind.

When several places need the same connection (the controller, a banner showing its errors, a
widget that reacts to one event), do not open it once per listener. The widget that owns the
feature opens it in `initState`, maps it to the feature's models, shares it (a broadcast
`StreamController` in a small session object), passes that stream (or the whole session, for a
two-way socket) to the controller's constructor, and closes it in `dispose`. The connection then
lives exactly as long as the screen.

A two-way connection (a WebSocket) needs three things the transport does not give:

- **Answers to calls.** Sending a message proves nothing: the network may be down, the server may
  reject it. Every command carries an id, and the server answers with a result or an error for
  that id; `rpc_connection.dart` (in Examples) keeps a `Completer` per id, fails it after a
  timeout, and fails every waiting call when the connection closes. The UI acts on the answer:
  clear the message field after the server accepted the message, not when it was sent, and show
  the error otherwise. Only what may be lost goes without an answer ("typing").
- **A heartbeat.** A dead connection can look open for minutes. The server pings every few seconds
  and the client answers (or the other way round); no message for two or three periods means the
  connection is gone: close it and reconnect.
- **Resync after a reconnect.** The server may have forgotten the client (the room, the
  subscription): join again and fetch what changed, as `onReconnected` does in
  `story_repository.dart`.

No `Mutex` around sending: Dart runs one event at a time, and `WebSocket.add` is synchronous.

A raw `Socket` is a stream of bytes, not of messages: one `listen` event may hold half a message
or three of them. Frame the messages (one JSON per line with `LineSplitter`, or a length prefix)
before decoding; decoding each chunk as one message works on localhost and fails on a real
network.

Polling sends the next request only after the previous one has finished: a loop with a delay
inside a stream (as in Pattern 1), not `Timer.periodic` with an `async` callback, which starts a new
request every period even while the last one is still waiting. Long polling (the server holds the
request until it has something or its timeout passes) asks again at once after an answer, but
waits after an error, longer each time: a loop that retries immediately when the server is down
or the phone is offline spins at full speed. Give the client a timeout a little longer than the
server's, and send the id of the last message received, so nothing is lost between requests.

Patches to a value (a full snapshot first, then deltas) are applied where the value is held: in the
controller that owns the state, or in the client's middleware when every caller wants whole values.

### Mistakes with streams

- A `try` / `catch` around building a stream catches nothing: `snapshots().map(...)` only builds it,
  and its errors arrive later, through the stream. Handle them in `listen(onError: ...)`, or with
  `handleError` where they can be turned into something useful.
- `asBroadcastStream()` subscribes to the source on the first listener and stays subscribed after
  the last one cancels: a Firestore listener or a socket stays open for good. A method that returns a
  new stream on every call needs no broadcast; when one is needed, use a broadcast
  `StreamController` with a clear owner.
- Listening twice to a single-subscription stream throws. Each call of a method like `events()`
  returns a new stream, so each listener calls the method.

## Decoding response bodies

The project's `ApiClient` decodes a JSON body from the bytes as UTF-8 itself (see "HTTP clients" in
`docs/rules/dependencies.md`). Code that reads `package:http` directly (a download, a non-JSON
endpoint) decodes text from the bytes itself, as UTF-8, unless the API says otherwise:

- `package:http`'s `Response.body` takes the charset from `Content-Type`. Without one it uses
  UTF-8 only for `application/json`; for `text/plain`, `text/html` or a missing header it falls
  back to latin1, and `Привет` comes out as `ÐÑÐ¸Ð²ÐµÑ` (checked with http 1.6.0;
  `charset=utf-8` in the header decodes correctly). Use `utf8.decode(response.bodyBytes)`.
- JSON goes from bytes to objects in one pass: `utf8.decoder.fuse(json.decoder).convert(bytes)`.
  On the VM that is a dedicated decoder (`_JsonUtf8Decoder`, checked) that builds no intermediate
  `String`; `decode` in `patterns.dart` (`docs/rules/dart.md`) uses it.
- Dio's default transformer (dio 5.11.1) decodes a JSON response the same way, strictly, but other
  text with `allowMalformed: true`: broken bytes become U+FFFD without an error. Where the text
  must be valid, request `ResponseType.bytes` and call `utf8.decode`, which throws a
  `FormatException`.

See "Strings and text length" in `docs/rules/dart.md` for counting and cutting the text.

## Local storage

Use SQLite, through `drift`, for anything beyond a few settings; `shared_preferences` for a handful
of small values (a flag, the last selected tab). Key-value stores written as Dart collections
(`hive`, `isar`, `get_storage`) are the wrong tool:

- **No migrations.** Changing a model breaks the data already on the users' devices; the only safe
  move left is to wipe the store on every release. Drift has versioned migrations with tests (see
  "Drift migration").
- **No transactions.** Two writes that must succeed together cannot be made atomic.
- **No queries.** No indexes, joins, relations, views, triggers or JSON functions: anything other
  than a lookup by key is a scan written by hand. SQL does it in the database.
- **Memory and isolates.** Boxes are kept in memory, and a box is not safe to open from several
  isolates; SQLite handles both.
- **Reliability and tooling.** SQLite is among the most tested software there is, is on every
  phone and browser, and opens in any database tool (DB Browser for SQLite, DBeaver, DataGrip), so
  QA can look inside. A corrupted Dart store has no recovery path.
- **Maintenance.** The original `hive` (2.2.3, 2022) and `isar` (3.1.0, 2023) have had no release
  for years; check pub.dev before relying on any fork.
- **Tests.** Drift opens an in-memory database (`NativeDatabase.memory()`), so a test touches no
  disk.

### Preference entries

Declare every `shared_preferences` value once, as an entry that owns its key and its encoding
(`preferences_entry.dart` in Examples), instead of string keys spread over the code: the key cannot
differ between the write and the read, and a value of any type gets one place to be encoded.

- Store an enum by `.name` and read it with `values.asNameMap()[stored]`: `toString()` also stores
  the type's name, and `values.firstWhere(...)` without `orElse` throws on a value from an older
  version.
- Store a `Color` with `toARGB32()`; `Color.value` is deprecated.
- Use `SharedPreferencesAsync` (or `SharedPreferencesWithCache`): the old `SharedPreferences`
  singleton is legacy.
- Tokens do not go here: see "Storing tokens" in `docs/rules/security.md`.

### Searching text

SQLite's own `lower()`, `upper()`, `LIKE` and `COLLATE NOCASE` fold case only for ASCII:
`'Газированная вода' LIKE '%газ%'` is false, while `'Water' LIKE '%water%'` is true. Do not fix it
with string functions in SQL; store a normalized copy instead:

- Add a search column (`name_search`) and fill it in Dart whenever the row is written: trim,
  collapse repeated spaces, drop characters that never matter, `toLowerCase()` (Dart folds Cyrillic
  and other scripts correctly). Check the resulting length.
- Normalize the query with the same function, then compare plainly:
  `filter.nameSearch.like('%$query%')`. Drift's `like` uses the pattern as given: the `%` are
  yours to add, and a `%` or `_` typed by the user is a wildcard unless escaped.
- Index the search column; `COLLATE NOCASE` on an index is enough only for ASCII-only values
  (emails, codes).
- For real full-text search (words, prefixes, ranking), use an FTS5 table: its default `unicode61`
  tokenizer folds case beyond ASCII.

### Files and blobs

Bytes (`Uint8List`) go into a drift `BlobColumn` (`BlobColumn get bytes => blob()();`):

- For many small files (thumbnails, avatars, cached responses) SQLite is as fast as the file
  system and often faster: about 35% for 10 KB blobs in SQLite's own measurements, with about 20%
  less disk space (https://www.sqlite.org/fasterthanfs.html), since it opens one file instead of
  one per blob.
- Large files (videos, big downloads) stay files on disk, with their path and metadata in a table:
  not because SQLite cannot hold them, but because a database of gigabytes is hard to back up, copy
  and shrink.
- `cached_network_image` works that way through `flutter_cache_manager`: metadata and relative paths
  in SQLite (`sqflite`), the bytes in files. On the web it does not cache at all; the browser's own
  cache does.
- Read a blob only when it is shown: select the metadata columns for lists, the blob for one row.

## Drift migration

Only add a local table when the feature really needs persistence. Never edit `*.g.dart` by hand.

### Steps

1. Put the table class in `lib/src/_core/database/tables/<name>_table.dart`.
2. Add the table to `@DriftDatabase(tables: [...])` in `lib/src/_core/database/database.dart`.
3. Bump `schemaVersion` by one.
4. Dump the new schema and regenerate the step helper:
   `dart run drift_dev schema dump lib/src/_core/database/database.dart drift_schemas/` then
   `dart run drift_dev schema steps drift_schemas/ lib/src/_core/database/database.steps.dart`.
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

### `preferences_entry.dart`

```dart
// file: preferences_entry.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One value in [SharedPreferencesAsync], declared once: its key and how it is written and read.
///
/// Reading and writing go through the same object, so the key cannot differ between them. A stored
/// value that [decode] no longer understands (an enum value that was renamed) reads as `null`.
final class PreferencesEntry<T extends Object> {
  const PreferencesEntry({
    required this._preferences,
    required this.key,
    required this._encode,
    required this._decode,
  });

  /// The key in the preferences.
  final String key;

  final SharedPreferencesAsync _preferences;
  final String Function(T value) _encode;
  final T? Function(String stored) _decode;

  /// The stored value, or `null` when there is none or it cannot be read.
  Future<T?> read() async => switch (await _preferences.getString(key)) {
    final String stored => _decode(stored),
    null => null,
  };

  /// Stores [value].
  Future<void> write(T value) => _preferences.setString(key, _encode(value));

  /// Removes the value.
  Future<void> remove() => _preferences.remove(key);
}

/// An entry for an enum, stored by its [Enum.name]: `toString()` would also store the type's name.
PreferencesEntry<E> enumEntry<E extends Enum>(
  SharedPreferencesAsync preferences,
  String key,
  List<E> values,
) {
  final byName = values.asNameMap();
  return PreferencesEntry<E>(
    preferences: preferences,
    key: key,
    encode: (value) => value.name,
    decode: (stored) => byName[stored],
  );
}

/// Saves the user's theme choices.
abstract interface class IThemeDataProvider {
  Future<Color?> readSeedColor();

  Future<void> setSeedColor(Color color);

  Future<ThemeMode?> readThemeMode();

  Future<void> setThemeMode(ThemeMode mode);
}

/// [IThemeDataProvider] in the device's preferences.
final class ThemeDataProviderLocal implements IThemeDataProvider {
  ThemeDataProviderLocal({required SharedPreferencesAsync preferences})
    : _seedColor = PreferencesEntry<Color>(
        preferences: preferences,
        key: 'theme.seed_color',
        encode: (color) => color.toARGB32().toString(),
        decode: (stored) => switch (int.tryParse(stored)) {
          final int argb => Color(argb),
          null => null,
        },
      ),
      _themeMode = enumEntry(preferences, 'theme.mode', ThemeMode.values);

  final PreferencesEntry<Color> _seedColor;
  final PreferencesEntry<ThemeMode> _themeMode;

  @override
  Future<Color?> readSeedColor() => _seedColor.read();

  @override
  Future<void> setSeedColor(Color color) => _seedColor.write(color);

  @override
  Future<ThemeMode?> readThemeMode() => _themeMode.read();

  @override
  Future<void> setThemeMode(ThemeMode mode) => _themeMode.write(mode);
}
```

### `payments_data_provider.dart`

```dart
// file: payments_data_provider.dart
import 'api_client.dart';
import 'app_exception.dart';

/// The failures of a payment that the app handles in their own way. Sealed: a `switch` over them
/// is checked by the compiler. Expected: the controller shows them and does not report them.
sealed class PaymentException extends ExpectedException {
  const PaymentException();
}

/// The balance does not cover the order: the app offers a top-up.
final class InsufficientFundsException extends PaymentException {
  const InsufficientFundsException();
}

/// The coupon has been used before: the app clears the coupon field.
final class CouponAlreadyUsedException extends PaymentException {
  const CouponAlreadyUsedException({required this.coupon});

  final String coupon;
}

/// A paid order.
final class Receipt {
  const Receipt({required this.id, required this.total});

  final String id;
  final int total;
}

/// Payments on the server.
abstract interface class IPaymentsDataProvider {
  /// Pays for [orderId].
  ///
  /// Throws a [PaymentException] for a failure the app handles, a [RejectedException] for one the
  /// user only reads, and passes every other one on.
  Future<Receipt> pay({required String orderId, String? coupon});
}

/// [IPaymentsDataProvider] over the app's [ApiClient].
final class PaymentsDataProviderRemote implements IPaymentsDataProvider {
  const PaymentsDataProviderRemote({required this._client});

  final ApiClient _client;

  @override
  Future<Receipt> pay({required String orderId, String? coupon}) async {
    final APIClientResponse response;
    try {
      response = await _client.post(
        '/payments',
        body: <String, Object?>{'order_id': orderId, 'coupon': ?coupon},
      );
    } on APIClientException$Client catch (error, stackTrace) {
      // A 4xx with the server's error body: `{"code": "insufficient_funds", "message": "..."}`.
      if (error.data case {'code': final String code}) {
        // A map pattern matches only when the key is there: the optional message is read apart.
        final message = switch (error.data) {
          {'message': final String message} => message,
          _ => null,
        };
        switch (code) {
          case 'insufficient_funds':
            Error.throwWithStackTrace(const InsufficientFundsException(), stackTrace);
          case 'coupon_used' when coupon != null:
            Error.throwWithStackTrace(CouponAlreadyUsedException(coupon: coupon), stackTrace);
          case 'order_closed' || 'card_declined':
            Error.throwWithStackTrace(RejectedException(code: code, message: message), stackTrace);
        }
      }
      rethrow; // An unknown code, another 4xx, no body: reported as it is.
    }
    return switch (response.body) {
      {'receipt': {'id': final String id, 'total': final int total}} => Receipt(
        id: id,
        total: total,
      ),
      final body => throw FormatException('Not a payment receipt', body),
    };
  }
}
```

### `rpc_connection.dart`

```dart
// file: rpc_connection.dart
import 'dart:async';

/// An error the server sent back for a call.
final class RpcException implements Exception {
  const RpcException(this.message);

  final String message;

  @override
  String toString() => 'RpcException: $message';
}

/// Calls over a two-way message connection, such as a WebSocket, that wait for the server's answer.
///
/// Every call carries an id, and the server answers it with a result or an error carrying the same
/// id; a message without an id is a push. The messages follow JSON-RPC 2.0:
/// `{"id": 1, "method": "send", "params": {...}}` out, `{"id": 1, "result": ...}` or
/// `{"id": 1, "error": {"message": "..."}}` back.
final class RpcConnection {
  RpcConnection({
    required Stream<Map<String, Object?>> incoming,
    required this._send,
    this.timeout = const Duration(seconds: 10),
  }) {
    _subscription = incoming.listen(
      _onMessage,
      onError: _pushes.addError,
      onDone: _onDone,
    );
  }

  /// How long a call waits for its answer.
  final Duration timeout;

  final void Function(Map<String, Object?> message) _send;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final StreamController<Map<String, Object?>> _pushes =
      StreamController<Map<String, Object?>>.broadcast();
  late final StreamSubscription<Map<String, Object?>> _subscription;
  int _nextId = 0;
  bool _closed = false;

  /// Messages the server sends on its own: someone joined, a message arrived.
  Stream<Map<String, Object?>> get pushes => _pushes.stream;

  /// Sends [method] and completes with the server's result.
  ///
  /// Fails with [RpcException] when the server answers with an error or the connection closes,
  /// and with [TimeoutException] after [timeout]. A call that timed out may still have run on the
  /// server: make such methods safe to repeat, or check on reconnect.
  Future<Object?> call(String method, [Object? params]) {
    if (_closed) {
      return Future<Object?>.error(const RpcException('The connection is closed'));
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    try {
      _send(<String, Object?>{'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    } on Object catch (error, stackTrace) {
      _pending.remove(id);
      return Future<Object?>.error(error, stackTrace);
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('No answer to "$method"', timeout);
      },
    );
  }

  /// Sends [method] without waiting for an answer: only for what may be lost, such as "typing".
  void notify(String method, [Object? params]) {
    if (_closed) return;
    _send(<String, Object?>{'jsonrpc': '2.0', 'method': method, 'params': ?params});
  }

  /// Stops listening, and fails every call still waiting for an answer.
  Future<void> close() async {
    if (_closed) return;
    await _subscription.cancel();
    _onDone();
  }

  void _onMessage(Map<String, Object?> message) {
    switch (message) {
      case {'id': final int id, 'error': final Object? error}:
        final text = switch (error) {
          {'message': final String text} => text,
          _ => '$error',
        };
        _pending.remove(id)?.completeError(RpcException(text));
      case {'id': final int id, 'result': final Object? result}:
        _pending.remove(id)?.complete(result);
      case {'method': String()}:
        _pushes.add(message);
      default:
        break;
    }
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    final waiting = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in waiting) {
      completer.completeError(const RpcException('The connection is closed'));
    }
    unawaited(_pushes.close());
  }
}
```

### `story_repository.dart`

```dart
// file: story_repository.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Listens to [connect] and opens it again whenever it ends or fails, until the listener cancels.
///
/// Waits [delay] before the first retry and doubles it up to [maxDelay]; an event resets it.
/// Errors reach the listener, and the stream goes on. [onReconnected] runs after every new
/// connection but the first, for example to fetch what was missed.
Stream<T> reconnecting<T>(
  Stream<T> Function() connect, {
  Duration delay = const Duration(seconds: 1),
  Duration maxDelay = const Duration(seconds: 30),
  Future<void> Function()? onReconnected,
}) {
  final controller = StreamController<T>();
  StreamSubscription<T>? subscription;
  Timer? retry;
  var wait = delay;
  var attempts = 0;

  void open() {
    if (controller.isClosed) return;

    void retryLater() {
      subscription = null;
      if (controller.isClosed) return;
      retry = Timer(wait, open);
      wait = Duration(microseconds: math.min(wait.inMicroseconds * 2, maxDelay.inMicroseconds));
    }

    final Stream<T> source;
    try {
      source = connect();
    } on Object catch (error, stackTrace) {
      controller.addError(error, stackTrace);
      retryLater();
      return;
    }
    if (attempts++ > 0 && onReconnected != null) {
      onReconnected().catchError(controller.addError).ignore();
    }
    subscription = source.listen(
      (event) {
        wait = delay;
        controller.add(event);
      },
      onError: (Object error, StackTrace stackTrace) {
        controller.addError(error, stackTrace);
        retryLater();
      },
      onDone: retryLater,
      cancelOnError: true,
    );
  }

  controller
    ..onListen = open
    ..onCancel = () async {
      retry?.cancel();
      await subscription?.cancel();
      subscription = null;
      await controller.close();
    };
  return controller.stream;
}

/// A message from the story feed.
@immutable
final class StoryEvent {
  const StoryEvent({required this.message});

  final String message;
}

/// One server-sent event: its name and its JSON data.
typedef SseEvent = ({String event, Map<String, Object?> data});

/// The story feed.
abstract interface class IStoryRepository {
  /// Events of the feed, reconnecting until the listener cancels.
  Stream<StoryEvent> events();
}

/// [IStoryRepository] over server-sent events. Holds no state: every [events] call is its own
/// connection, opened on listen and closed on cancel.
final class StoryRepositoryImpl implements IStoryRepository {
  const StoryRepositoryImpl({required this._connect, required this._token});

  /// Opens one SSE connection, such as `(path, headers) => sse(baseUrl + path, headers: headers)`.
  final Stream<SseEvent> Function(String path, Map<String, String> headers) _connect;
  final String Function() _token;

  @override
  Stream<StoryEvent> events() => reconnecting(
    // Read the token on every connection: it may have been refreshed since the last one.
    () => _connect('/api/story', <String, String>{'Authorization': 'Bearer ${_token()}'}),
  ).expand(
    (event) => switch (event) {
      (event: 'story', data: {'message': final String message}) => <StoryEvent>[
        StoryEvent(message: message),
      ],
      _ => const <StoryEvent>[],
    },
  );
}
```

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
        (await read()).forEach(controller.add);
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
