---
name: isolates
description: "Isolates: Isolate.run for one CPU-heavy job or native call, a stream of results from one job, splitting work by a time budget where no isolate is available, a typed worker for a long-lived one, what can be sent (errors included), stopping an isolate, plugins in an isolate, and Android background work and foreground services."
---

# Isolates

## Rules

- Move CPU-bound work (decoding a large JSON, parsing, hashing, image work, and synchronous FFI
  calls into native code) off the UI isolate with `Isolate.run` or `compute`. I/O needs no
  isolate. The web has no isolates: `compute` runs the function on the main thread there, so a
  long loop yields with `await Future<void>.delayed(Duration.zero)` between chunks. See
  "Choosing".
- One job that produces many results (files found, images compressed one by one) is a `Stream`
  from `isolateStream`: values and errors arrive in order, the stream ends when the isolate does,
  and cancelling it kills the isolate. Not a hand-made `Isolate.spawn` with a "done" string. See
  "A stream of results".
- A job takes its data as arguments and captures nothing else. A closure written in an instance
  method captures `this`: copy the fields it needs into local variables first. See "Sending data".
- An error crosses as it is: send `(error, stackTrace)`, both objects. No text joined with a
  separator and parsed back. See "Sending data".
- Code in an isolate stops by returning or with `Isolate.exit`; `Isolate.current.kill()` lets the
  code after it run on. An app never calls `exit` or kills its root isolate. See "Health and
  stopping".
- Statics, top-level variables, `Dependencies`, error handlers and `Controller.observer` exist once
  per isolate. Build what an isolate needs in its entry point from plain data; never send a
  service. See "State is per isolate".
- A long-lived worker is one class: typed requests matched by id, a start timeout, `onError` and
  `onExit` ports, and a `close()` that asks the isolate to stop, then kills it with
  `Isolate.immediate`. Its owner registers `close` with its `Disposer`. See "A worker isolate".
- `Isolate.ping` tells a dead isolate from a live one, not a stuck one from a working one: give
  requests a timeout instead. See "Health and stopping".
- A plugin in another isolate needs `BackgroundIsolateBinaryMessenger.ensureInitialized` with the
  root isolate's `RootIsolateToken`. See "Plugins in an isolate".
- On Android, background work goes to a push message, WorkManager or a purpose-built API first. A
  foreground service is for work the user started and can see; it declares its type and the
  permission for that type. See "Android: background work and foreground services".

## Choosing

- **One job: `Isolate.run(() => parse(body))`.** It spawns an isolate, runs the function, returns
  its result and ends the isolate. The arguments are copied in; the result comes back through
  `Isolate.exit`, which hands it over without copying (SDK doc). If the function throws,
  `Isolate.run` throws the same error (checked: an `ArgumentError` arrives as an `ArgumentError`);
  an uncaught asynchronous error inside it arrives as a `RemoteError`, which carries only the
  error's and the stack's text.
- **When it pays.** The spawn itself is cheap; the work has to be long enough to show. Measured in
  an AOT build on an M-series Mac: an empty `Isolate.run` took 0.04 ms, `jsonDecode` took 0.6 ms
  for 100 KB and 4.9 ms for 1 MB (a frame is 16 ms at 60 Hz, 8 ms at 120 Hz). A phone is slower:
  measure in profile mode on the slowest target device, and move the work once it costs a visible
  part of a frame. A size threshold of a few KB moves nothing that mattered.
- **Many results from one job: `isolateStream(() => findImages(path))`.** The values arrive as a
  stream while the job runs; the stream ends with the isolate and fails if it dies. See "A stream
  of results".
- **`compute(fn, message)`** (`package:flutter/foundation.dart`) is `Isolate.run` with a debug
  label on native platforms. On the web it awaits once and then calls `fn` on the main thread
  (`_isolates_web.dart`), so a long job still freezes the page there: make the job smaller, or
  move it to a Web Worker.
- **A worker isolate** when the isolate keeps state between requests (a warm cache, a loaded
  model, an open native handle) or answers many small requests that would each pay for a spawn.
  See "A worker isolate".
- **Synchronous native calls block too.** An FFI call (`@Native` or a `DynamicLibrary` lookup, as
  in native image, crypto or database packages) runs on the calling isolate's thread and blocks
  its event loop until it returns, however fast the native code is: no frames, timers or input
  meanwhile (checked: a 10 ms periodic timer ticked 0 times during a 1 s native `sleep`, and 51
  times in 500 ms while the same call ran inside `Isolate.run`). Run a heavy native job, from
  decoding to encoding, inside one `Isolate.run` and return plain bytes (`Uint8List`): a native
  handle is `Finalizable` and cannot be sent (see "Sending data"), so it is created, used and
  disposed in the same isolate.
- **Splitting work on the UI isolate**, where no isolate is available (the web) or the work needs
  objects that cannot be sent. Only an event gives the event loop a turn:
  `await Future<void>.delayed(Duration.zero)` between chunks (`map_in_chunks.dart` in Examples).
  `await null`, `Future.microtask`, `Stream.fromIterable` and an `async*` generator continue in
  microtasks, which all run before the next event, so a "lazy" stream over a list lets nothing in
  (checked: a zero-duration timer scheduled before a 200-item loop fired after all 200 items with
  each of these, and after the first 20 with `Future.delayed(Duration.zero)` every 20 items).
  Frames and input wait the same way, since the engine delivers them as events. Yield by time, not
  by a count of items: a `Stopwatch` measures the chunk, and the loop yields once it has run for
  the budget, so one slow item cannot stretch a chunk past a frame. Keep the budget under half a
  frame (4 ms covers 120 Hz). One synchronous call (a single `jsonDecode`) cannot be split: only
  the work after it can.
- **No `Isolate.spawnUri` in an app.** It starts a new isolate group from a URI, and in an AOT
  build (every Flutter release build) the URI must point to a precompiled AOT snapshot (checked: a
  `dart compile exe` program failed with "does not contain a valid AOT snapshot" for a `.dart`
  file that the JIT ran). Use `Isolate.run` or `Isolate.spawn`.
- **No isolate for I/O.** Files, sockets and `http` are already asynchronous: the waiting happens
  outside Dart and does not block the event loop. An isolate helps with the Dart code that runs
  long after the bytes arrive (decoding the response, not downloading it). A download inside an
  isolate copies every byte back to the caller and takes the HTTP client's cancellation and
  progress out of reach.
- An isolate is an implementation detail of a repository or data provider, behind its interface:
  its methods already return `Future`s. Tests replace the repository; `Isolate.run` does not run
  on fake time (see `docs/rules/testing.md`).

## Sending data

- A message is copied into the receiving isolate; immutable objects such as strings are shared.
  Between isolates of the same program (`Isolate.spawn`, `Isolate.run`) almost any object can be
  sent, except a `ReceivePort`, objects with native resources (a `Socket`), a `DynamicLibrary`, a
  `Finalizer` or `Finalizable`, and instances of classes marked `@pragma('vm:isolate-unsendable')`
  (`SendPort.send` doc). Records are sendable; a request is a record or a class of plain fields.
- A closure sends everything it captures, and the VM may capture more than the closure uses
  (`SendPort.send` doc, dartbug 36983). A closure created in an instance method captures `this`:
  the whole object goes along, or the send fails because one field cannot be sent. Checked:
  `Isolate.run(() => value + 1)` inside a class with a `ReceivePort` field throws `ArgumentError`
  ("object is unsendable"); after `final v = value;` the same call with `v` works. Pass a
  top-level or static function, or copy into locals first.
- Arguments go in one record or class, typed: `Isolate.spawn(_main, (port, path, token))`, not a
  `List<dynamic>` read back with `args[1] as String`.
- **Errors cross as they are.** An exception object and its `StackTrace` can be sent like any
  other object: `port.send((error, stackTrace))` (checked: a custom exception arrived with its
  fields, the stack as a `StackTrace`; `Isolate.run` does the same). Send the pair, and add it on
  the receiving side with `addError(error, stackTrace)` or `completeError`. Only an error that
  holds something unsendable (a port, a socket) makes `send` throw `ArgumentError`: then send
  `RemoteError('$error', '$stackTrace')`. No error text joined with a separator and split again.
- Large binary results: return them from `Isolate.run` (no copy). Bytes going into a worker go in
  a `TransferableTypedData.fromList(...)`: creating it copies the bytes once, sending it takes
  constant time, and the receiver calls `materialize()` once (SDK doc).

## State is per isolate

Each isolate has its own heap: statics and top-level variables start fresh in it (checked: a
static set to 5 in the main isolate reads 0 inside `Isolate.run`). A "singleton" is therefore one
instance per isolate: a worker or a background engine gets its own, with its own state. The rules
pass dependencies through constructors anyway (see "Pure DI, not a service locator" in
`docs/rules/dependencies.md`); this is one more reason a static holder is not "the" instance.

- A worker or a background entry point does not have the app's `Dependencies`, its error handlers,
  its `Controller.observer` or its caches. Build what it needs in its entry point from plain
  arguments (a file path, a config, a token) and give it its own error reporting.
- Pass data, not services: a repository holds clients, ports and controllers that cannot be sent,
  and a copy of one would not share anything with the original.

## A stream of results

One job, many results, in order, while the user watches them arrive: the files of a folder with
their thumbnails, the images of a gallery compressed one by one, the lines of a large file parsed.
`isolate_stream.dart` (in Examples) runs a `Stream` function on a new isolate:

```dart
Stream<ImageFile> compressedImages(String folder) {
  final token = RootIsolateToken.instance!; // read here: it is null in any other isolate
  return isolateStream(() async* {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    await for (final file in Directory(folder).list()) {
      if (isImage(file.path)) yield await compress(file.path);
    }
  }, debugName: 'Compress $folder');
}
```

A repository returns it as is, and the controller or bloc listens with `await for` or
`emit.forEach`. What `isolateStream` does that a hand-made `Isolate.spawn` usually misses:

- **The input goes in the spawn argument.** Everything the job needs is known when it starts, so
  there is no handshake. Sending the isolate's own `SendPort` back (`Completer<SendPort>`) is
  needed only when the owner keeps sending it requests: that is a worker (see "A worker
  isolate").
- **The end is the isolate's exit, not a message.** The job's stream ending (or its error) ends
  the isolate with `Isolate.exit()`, and its `onExit` message closes the stream. All values sent
  before it arrive first (checked with 100,000 messages). A "done" string can be sent too early:
  a recursive helper that sends it at the end of every level ends the stream after the first
  subfolder.
- **A dead isolate fails the stream.** `onError` and `onExit` go to the same port, so an uncaught
  error (a throwing timer) arrives as a `RemoteError` and the stream ends. Without them, an
  `await for` over the port waits forever and keeps the port, and the isolate holding it, open.
- **`Isolate.exit()` at the end, not just `return`.** An isolate lives while it has an open port
  or a pending timer. A job that leaves one behind, or an error object holding a `ReceivePort`,
  keeps the isolate running and the stream open after the last value (checked: the stream never
  ended until the entry point called `Isolate.exit()`).
- **Cancelling kills the isolate.** Cancelling a subscription to a `ReceivePort` only closes the
  port: the isolate keeps working and its messages go nowhere (checked: after `take(3)`, the
  isolate still answered a ping). `isolateStream` kills it with `Isolate.immediate` in `onCancel`
  (checked: without that call, it sent 38 more messages in the time it otherwise sent 10). A
  screen that closes stops the compression it started.
- **No backpressure.** Pausing the subscription buffers values on the owner's side; the isolate
  keeps producing. For a job whose output does not fit in memory, write to a file in the isolate
  and stream the paths, or use a worker and ask for the next batch.

## A worker isolate

`isolate_worker.dart` (in Examples) is the shape:

- **One class owns the isolate.** Callers see `Future<Response> request(Request)`. Each request
  carries an id; the worker answers `(id, result, null)` or `(id, error, stack)`, and the owner
  completes a `Completer` per id, as `rpc_connection.dart` does for a socket in
  `docs/rules/repositories.md`. No broadcast stream between the two sides: it drops events sent
  before its first listener, and a caller cannot tell which output answers which input.
- **The handshake has a timeout.** The worker's first message is its `SendPort`; if it does not
  arrive, the isolate is killed and `spawn` fails instead of hanging.
- **The handler's errors are answers.** The worker catches them and sends them back, so one bad
  request does not end the isolate (checked). For what it cannot catch, `Isolate.spawn` gets
  `onError` and `onExit` ports: an uncaught error arrives as a two-element list of strings
  `[error, stackTrace]` (the error object itself does not cross), the end of the isolate as
  `null`. On either, every request still waiting fails (checked: an unawaited error in the handler
  ends the worker and fails the waiting request with a `RemoteError`). `Isolate.spawn` defaults to
  `errorsAreFatal: true`.
- **An open `ReceivePort` keeps its isolate alive** until it is closed (`RawReceivePort` doc). The
  worker stops by closing its command port when it receives the stop message; the owner's ports,
  left open, keep the owner's isolate alive too (a script that never exits).
- **It is created where long-lived things are created.** `spawn` is asynchronous, so it runs in an
  initialization step (see `docs/rules/dependencies.md`) or in the scope that owns the worker; the
  worker reaches repositories through their constructors, and the owner registers
  `disposer.defer('Stop the parser', worker.close)` (see "Release in reverse order" in
  `docs/rules/repositories.md`). A repository does not spawn one per call.
- Give it a `debugName`: it shows in DevTools and the logs.

## Health and stopping

- `Isolate.ping(port, priority: Isolate.immediate)` is answered by the VM even while the isolate
  runs a long synchronous loop (checked: answered at once by an isolate in `while (true) {}`). A
  ping watchdog therefore finds only an isolate that is gone, and `onExit` reports that without
  polling. To find a stuck handler, give requests a timeout (`request(x, timeout: ...)`); on
  timeout, close the worker and spawn a new one.
- `kill()` uses `beforeNextEvent`: it waits until the isolate returns to its event loop, which a
  synchronous loop never does (checked: still running 500 ms after `kill()`).
  `kill(priority: Isolate.immediate)` ends it at once (checked). Stop in two steps: a stop message
  and a grace period for the isolate to finish what it holds, then `Isolate.immediate`. A request
  still running when the stop message arrives completes normally (checked).
- **Inside the isolate, `Isolate.current.kill()` is not a `return`.** It too waits for the next
  event, so the code after it keeps running (checked: four more messages arrived after it). Stop
  by returning from the entry point with no port left open, or with `Isolate.exit(port, last)`:
  it sends one last message (handed over without copying) and ends the isolate at once, without
  running pending `finally` blocks.
- **Never `exit(0)` and never kill the root isolate in an app.** Both end the whole app, and the
  user sees a crash. Stop the work, not the program.
- **`Future.timeout` does not stop the work.** It completes the returned future after the limit;
  the original keeps running and its result is ignored (`Future.timeout` doc example). To stop a
  job after a timeout, kill its isolate (`isolateStream` cancels, a worker's `close`), or check a
  cancellation flag in the loop.

## Plugins in an isolate

A spawned isolate has no platform channels. Read `RootIsolateToken.instance` in the root isolate
(it is `null` in any other), pass it as an argument, and call
`BackgroundIsolateBinaryMessenger.ensureInitialized(token)` first in the isolate; after that,
plugins that talk over platform channels work there (`background_prefs.dart` in Examples; checked
on macOS: `SharedPreferencesAsync` in `Isolate.run` read a value the root isolate wrote, with only
this call).

- A plugin that registers its Dart platform class itself keeps it in a static, which is empty in
  a new isolate like any other static. If a plugin reports that its platform instance is not set,
  `DartPluginRegistrant.ensureInitialized()` (never on the root isolate, per its doc) runs that
  registration; shared_preferences did not need it on macOS.
- A plugin that needs an `Activity`, a view or a permission dialog belongs to the root isolate.

## Android: background work and foreground services

### Choosing

A foreground service with its own Flutter engine is the heaviest option: a notification for as
long as it runs, a declared type, Play Console review, and limits that grow with every Android
release. Use the lighter tools first:

- **An event on the server**: a push message (FCM). A high-priority message is also one of the
  cases in which an app in the background may start a foreground service.
- **Deferrable or periodic work** (a sync, an upload that may wait for Wi-Fi): WorkManager, through
  the `workmanager` package. Android's docs point `dataSync` services there too.
- **A purpose-built API** where one exists: a media session for playback, the companion device
  manager for a paired device, geofencing for "when the user arrives". Android's docs list them
  under "Alternatives" for each service type.
- **A foreground service** only for work the user started, knows about and expects to continue
  with the app in the background: navigation, a long transfer, a call, a live connection to a
  device. `flutter_foreground_task` wraps the service and the Dart side; check any such package
  as `docs/rules/package-freshness.md` says before adding it.

### Checklist

From Android's docs (foreground service types, launch, background-start restrictions, Android 15
behavior changes, `Service` reference); the native code is Kotlin and not compiled here.

- **Type and permission (Android 14, API 34).** Each `<service>` declares
  `android:foregroundServiceType`, and the manifest requests the matching permission
  (`FOREGROUND_SERVICE_DATA_SYNC` for `dataSync`, `FOREGROUND_SERVICE_LOCATION` for `location`,
  ...) in addition to `FOREGROUND_SERVICE`. A missing permission throws `SecurityException` when
  the service is promoted. Some types also need a runtime permission granted first (`location`,
  `camera`, `microphone`, `health`). `specialUse` declares its reason in a `<property
  android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE">`, reviewed in the Play Console,
  where apps targeting 34+ declare all their types.
- **Promote with the type.** `ServiceCompat.startForeground(service, id, notification, type)`,
  ordinarily in `onStartCommand`, after `context.startForegroundService(intent)`. The id is
  positive (not 0), and a type not declared in the manifest throws `IllegalArgumentException`.
- **No start from the background (Android 12, API 31).** An app in the background cannot start a
  foreground service: `ForegroundServiceStartNotAllowedException`. The exemptions include a user
  action on a notification or widget, a high-priority FCM message, an exact alarm for an action
  the user asked for, the `BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED` and `MY_PACKAGE_REPLACED`
  broadcasts, and disabled battery optimization. A Dart timer that restarts the service while the
  app is in the background throws. Types that need while-in-use permissions (`camera`,
  `location`, `microphone`, body sensors) cannot be created from the background at all on
  Android 14 (`SecurityException`), with a few listed exceptions.
- **No start at boot for some types (apps targeting Android 15, API 35).** A `BOOT_COMPLETED`
  receiver may not start `dataSync`, `camera`, `mediaPlayback`, `phoneCall`, `mediaProjection` or
  `microphone` services (`ForegroundServiceStartNotAllowedException`). Test with
  `adb shell am compat enable FGS_BOOT_COMPLETED_RESTRICTIONS <package>` and
  `adb shell am broadcast -a android.intent.action.BOOT_COMPLETED <package>`.
- **Time limit for `dataSync` and `mediaProcessing` (apps targeting Android 15).** Six hours in 24,
  shared by all the app's services of that type, reset when the user brings the app to the
  foreground. Then the system calls `Service.onTimeout(int, int)`, and the service has a few
  seconds to call `stopSelf()`, or the app crashes with `RemoteServiceException`. Implement
  `onTimeout`. Test with `adb shell am compat enable FGS_INTRODUCE_TIME_LIMITS <package>` and
  `adb shell device_config put activity_manager data_sync_fgs_timeout_duration <ms>`.
  `shortService` runs about 3 minutes, needs no type permission and cannot be sticky.
- **The notification (Android 13, API 33).** `POST_NOTIFICATIONS` is a runtime permission. The
  service starts without it, but its notification then appears only in the Task Manager, not in
  the notification drawer. Use a priority of at least `PRIORITY_LOW`. Create the channel once;
  deleting it on every stop drops the user's settings for it.
- **Stopping.** `stopForeground(boolean)` is deprecated since API 33: call
  `stopForeground(STOP_FOREGROUND_REMOVE)` (or `ServiceCompat.stopForeground`), then `stopSelf()`.
- **Restart after the process dies.** With `START_STICKY`, `onStartCommand` receives a `null`
  intent when the service is restarted after its process has gone away (`onStartCommand` doc).
  Handle it: read the saved configuration and run the same start path, including
  `startForeground`.
- **Manifest details.** The permission for boot is `RECEIVE_BOOT_COMPLETED`;
  `android.permission.BOOT_COMPLETED` and `QUICKBOOT_POWERON` are not permissions
  (`Manifest.permission` has neither; `QUICKBOOT_POWERON` is an action some vendors send, and
  belongs in the receiver's `intent-filter`). A service that only the app starts is
  `android:exported="false"`: an exported one can be started by other apps.

### A service with its own Flutter engine

- The service runs a second engine, which is a separate isolate in the same process: it shares no
  objects with the app's engine (see "State is per isolate"). Its entry point is a top-level
  function annotated `@pragma('vm:entry-point')`, so the AOT compiler keeps it.
  `PluginUtilities.getCallbackHandle(fn)` gives a handle to send to the native side, and `null`
  for anything but a top-level or static function (its doc).
- The entry point has no `runApp`. It initializes a binding so platform channels work, builds its
  own dependencies and installs its own error handler (see "Uncaught errors" in
  `docs/rules/dependencies.md`).
- The app and the service talk through the native side (pigeon host and Flutter APIs on each
  engine). What the UI shows (opening, running, stopping, stopped) is the native side's answer to
  "is it running", checked on start; not a status set from an optimistic callback.
- On the Dart side the service is an interface (`open`, `close`, `isRunning`, a stream of status
  changes) with a pigeon-backed implementation passed in through the constructor, and a
  controller with a sealed state over it: not a singleton controller that creates its own API
  object.
- Teardown is a reverse-order list where every step is caught, as `Disposer` does (see
  "Releasing resources" in `docs/rules/repositories.md`).

## Mistakes to avoid

- **Listening to a `ReceivePort` twice.** It is a single-subscription stream (checked: the second
  `listen` throws `StateError`). `asBroadcastStream()` lets two listeners in but drops what
  arrives before each one listens.
- **Code after `await for` over a port.** The loop ends only when the port closes; a `return`
  after it is never reached while the isolate lives. End the loop on the last message, or let
  `isolateStream` end the stream.
- **A string message as a signal** (`'kill'`, `'done'`, `'error'`). It can collide with data, it
  is sent too early from a recursive helper, and it carries no error. Use typed records or
  classes, and `onExit` for the end.
- **An error turned into an empty result.** An isolate that catches its error and sends `[]` or
  `null` hands the caller a "successful" empty answer (a video saved without its sound). Send the
  error; the caller decides.
- **An isolate nobody stops.** Setting the field that held the `Isolate` to `null` does not end
  it, and neither does cancelling the stream over its port. Kill it in the owner's `dispose` or
  `onCancel`.
- **An open sink in an isolate.** `File.openWrite()` holds a file handle until `close()`; an
  isolate that ends without awaiting `close()` loses the buffered bytes (checked: 0 of 1,000
  bytes reached the file from `Isolate.run`, all 1,000 with `await sink.close()`). Await
  `close()` before sending the result.
- **Sending a big result back from `Isolate.spawn`.** `send` copies it (checked: the object that
  came back was not `identical` to the one sent, and the item the isolate added to its list was
  missing from the original). Return it with
  `Isolate.exit(port, result)` or `Isolate.run`, which hand it over, or send a file path.

## Examples

### `isolate_stream.dart`

Tested: streams 10,000 values in order and ends, a closure over a local works, an error arrives
as the same object after the values before it and ends the stream, an error holding a port
arrives as a `RemoteError`, an uncaught error in a timer fails and ends the stream, a job that
leaves a periodic timer running still ends, cancelling stops the work in the isolate (and the
test fails when the kill is removed), a pause buffers without losing values.

```dart
// file: isolate_stream.dart
import 'dart:async';
import 'dart:isolate';

/// Runs [job] on a new isolate and streams the values it emits.
///
/// The stream ends when [job]'s stream is done, fails with its error (the same object, when it
/// can be sent), and fails with a [RemoteError] when the isolate dies of an uncaught error.
/// Cancelling the subscription kills the isolate. Like `Isolate.run`, [job] must capture only
/// what it needs: a top-level or static function, or a closure over local variables.
///
/// The isolate does not wait for the listener: while the subscription is paused, its values are
/// buffered here.
Stream<T> isolateStream<T>(Stream<T> Function() job, {String? debugName}) {
  final controller = StreamController<T>();
  RawReceivePort? port;
  Isolate? isolate;
  var cancelled = false;

  void close() {
    port?.close(); // an open port keeps this isolate alive
    port = null;
  }

  controller
    ..onListen = () async {
      final receive = port = RawReceivePort()
        ..handler = (message) {
          switch (message) {
            case (final T value,):
              controller.add(value);
            case (final Object error, final StackTrace stackTrace):
              controller.addError(error, stackTrace);
            case [final Object? error, final Object? stack]: // onError: two strings, then exit
              final remote = RemoteError('$error', '$stack');
              controller.addError(remote, remote.stackTrace);
            case null: // onExit: every value was sent before it
              close();
              unawaited(controller.close());
          }
        };
      try {
        isolate = await Isolate.spawn<(SendPort, Stream<T> Function())>(
          _run<T>,
          (receive.sendPort, job),
          onError: receive.sendPort,
          onExit: receive.sendPort,
          debugName: debugName,
        );
        if (cancelled) isolate?.kill(priority: Isolate.immediate);
      } on Object catch (error, stackTrace) {
        close();
        controller.addError(error, stackTrace);
        unawaited(controller.close());
      }
    }
    ..onCancel = () {
      cancelled = true;
      // Nobody listens any more: stop the work.
      isolate?.kill(priority: Isolate.immediate);
      close();
    };
  return controller.stream;
}

/// The isolate's entry point: sends every value as a one-element record and an error as
/// `(error, stackTrace)`, then ends the isolate. `Isolate.exit` ends it even when the job left a
/// timer or an open port behind, and its `onExit` message tells the owner the stream is done.
Future<void> _run<T>((SendPort, Stream<T> Function()) argument) async {
  final (port, job) = argument;
  try {
    await for (final value in job()) {
      port.send((value,));
    }
  } on Object catch (error, stackTrace) {
    try {
      port.send((error, stackTrace));
    } on Object {
      // The error holds something that cannot be sent (a port, a socket): send its text.
      port.send((RemoteError('$error', '$stackTrace'), stackTrace));
    }
  }
  Isolate.exit();
}
```

### `isolate_worker.dart`

Tested: answers in order, an error in the handler keeps the worker running, `close` lets a running
request finish, kills a busy isolate within the grace period and fails what waits, an uncaught
error ends the worker and fails the waiting request.

```dart
// file: isolate_worker.dart
import 'dart:async';
import 'dart:isolate';

/// Runs on the worker isolate for every request. A top-level or static function (or a tear-off
/// of one), so that sending it to the isolate captures nothing.
typedef WorkerHandler<Request extends Object, Response extends Object?> =
    FutureOr<Response> Function(Request request);

/// One long-lived worker isolate that answers typed requests.
///
/// Every request carries an id and gets exactly one answer: the handler's result, its error as a
/// [RemoteError], or an error when the isolate ends. Nothing is left waiting forever.
final class IsolateWorker<Request extends Object, Response extends Object?> {
  IsolateWorker._(this._isolate, this._receive, this._commands);

  /// Starts the isolate and waits [startTimeout] for its command port.
  static Future<IsolateWorker<Request, Response>>
  spawn<Request extends Object, Response extends Object?>(
    WorkerHandler<Request, Response> handler, {
    Duration startTimeout = const Duration(seconds: 5),
    String? debugName,
  }) async {
    final receive = ReceivePort();
    final ready = Completer<SendPort>();
    IsolateWorker<Request, Response>? worker; // set once the handshake is done
    receive.cast<Object?>().listen((message) {
      switch (message) {
        case SendPort port when !ready.isCompleted:
          ready.complete(port);
        case (final int id, final Object? value, null):
          worker?._answer(id, value);
        case (final int id, final String error, final String stack):
          worker?._answerError(id, RemoteError(error, stack));
        case [final Object? error, final Object? stack]: // onError: two strings
          worker?._fail(RemoteError('$error', '$stack'));
        case null: // onExit
          if (!ready.isCompleted) ready.completeError(StateError('The isolate exited at start'));
          worker?._fail(StateError('The isolate exited'));
      }
    });
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<(SendPort, WorkerHandler<Request, Response>)>(
        _main<Request, Response>,
        (receive.sendPort, handler),
        onError: receive.sendPort,
        onExit: receive.sendPort,
        debugName: debugName,
      );
    } on Object {
      receive.close(); // an open port keeps this isolate alive
      rethrow;
    }
    try {
      final commands = await ready.future.timeout(startTimeout);
      return worker = IsolateWorker._(isolate, receive, commands);
    } on Object {
      isolate.kill(priority: Isolate.immediate);
      receive.close();
      rethrow;
    }
  }

  static void _main<Request extends Object, Response extends Object?>(
    (SendPort, WorkerHandler<Request, Response>) argument,
  ) {
    final (toOwner, handler) = argument;
    final commands = ReceivePort();
    toOwner.send(commands.sendPort);
    commands.cast<Object?>().listen((message) async {
      if (message case (final int id, final Request request)) {
        try {
          toOwner.send((id, await handler(request), null));
        } on Object catch (error, stackTrace) {
          toOwner.send((id, '$error', '$stackTrace')); // one bad request does not end the worker
        }
      } else {
        commands.close(); // stop: with no open port left, the isolate ends after this event
      }
    });
  }

  final Isolate _isolate;
  final ReceivePort _receive;
  final SendPort _commands;
  final Map<int, Completer<Response>> _pending = <int, Completer<Response>>{};
  int _nextId = 0;
  bool _closed = false;

  /// Sends [request]; completes with the handler's result, or fails after [timeout].
  Future<Response> request(Request request, {Duration? timeout}) {
    if (_closed) return Future<Response>.error(StateError('The worker is closed'));
    final id = _nextId++;
    final completer = _pending[id] = Completer<Response>();
    _commands.send((id, request));
    if (timeout == null) return completer.future;
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('No answer to request $id', timeout);
      },
    );
  }

  void _answer(int id, Object? value) => _pending.remove(id)?.complete(value as Response);

  void _answerError(int id, RemoteError error) => _pending.remove(id)?.completeError(error);

  void _fail(Object error) {
    _closed = true;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
  }

  /// Asks the isolate to stop, waits [grace] for it to finish, then kills it.
  Future<void> close({Duration grace = const Duration(seconds: 2)}) async {
    if (_closed) return;
    _closed = true;
    final exited = ReceivePort();
    _isolate.addOnExitListener(exited.sendPort);
    _commands.send(null);
    try {
      await exited.first.timeout(grace);
    } on TimeoutException {
      // A handler in a long synchronous loop never returns to the event loop, so plain kill()
      // would wait forever: immediate stops it at once.
      _isolate.kill(priority: Isolate.immediate);
    } finally {
      exited.close();
      _receive.close();
      _fail(StateError('The worker is closed'));
    }
  }
}
```

### `map_in_chunks.dart`

Tested: with items of 1 ms each and a 4 ms budget, a timer scheduled before the call runs after 4
to 6 items, not after all 40; one 10 ms item ends its chunk (the timer runs after it); a budget of
zero throws `ArgumentError`.

```dart
// file: map_in_chunks.dart
/// Maps [items] with [convert] on the current isolate, and lets the event loop run timers, input
/// and frames each time [budget] has passed.
///
/// A time budget, not a count of items: one slow item cannot stretch a chunk past a frame. Keep
/// [budget] under half a frame (16 ms at 60 Hz, 8 ms at 120 Hz) so the frame has time too.
///
/// For when no isolate is available (the web) or [convert] needs objects that cannot be sent;
/// elsewhere use `Isolate.run`.
Future<List<R>> mapInChunks<T, R>(
  List<T> items,
  R Function(T item) convert, {
  Duration budget = const Duration(milliseconds: 4),
}) async {
  if (budget <= Duration.zero) {
    throw ArgumentError.value(budget, 'budget', 'must be positive');
  }
  final results = <R>[];
  final chunk = Stopwatch()..start();
  for (var i = 0; i < items.length; i++) {
    results.add(convert(items[i]));
    if (chunk.elapsed >= budget && i + 1 < items.length) {
      // An event, not a microtask: `await null`, `Future.microtask`, `Stream.fromIterable` and
      // `async*` continue before any timer, input or frame gets its turn.
      await Future<void>.delayed(Duration.zero);
      chunk.reset();
    }
  }
  return results;
}
```

### `background_prefs.dart`

```dart
// file: background_prefs.dart
import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;

import 'package:flutter/services.dart' show BackgroundIsolateBinaryMessenger;
import 'package:shared_preferences/shared_preferences.dart';

/// Reads a preference on another isolate: a plugin there needs the root isolate's token.
///
/// The token and the key are read here, in the root isolate, so the closure captures only them.
Future<String?> readInBackground(String key) {
  final token = RootIsolateToken.instance;
  if (token == null) throw StateError('Call it from the root isolate');
  return Isolate.run(() {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    return SharedPreferencesAsync().getString(key);
  });
}
```
