---
name: controllers
description: "StateController with one state recipe (idle, processing, successful, error, all carrying data), handlers, one concern per controller, mutation features, paginated lists and testing states."
---

# Controllers

## Rules

- Extend `StateController<XState>` and run every action in `handle(() async {...})`.
- States are freezed and always the same four: `idle`, `processing`, `successful`, `error`. Every
  one carries the controller's current data (`XState.idle(data: ...)`), so the screen never loses
  what it shows. One recipe for every action: see "One recipe for states".
- No state per event (`loginProgress`, `authenticated`, `notAuthenticated`, ...): a new action
  reuses the same four states. A flag the UI needs is a getter on the state
  (`bool get isAuthenticated => user is AuthenticatedUser;`).
- `error` is a moment, not a place: the next state is `idle` again. Widgets show an error from the
  `listener` of `StateConsumer` (a SnackBar or banner with a retry); the `builder` renders the data.
- The `error` state holds the error object, never a display string (`message`): the widget turns it
  into text with `errorText(lcl, error)` (see "Error messages" in `docs/rules/localization.md`). A
  controller has no `BuildContext` and so no localization.
- Rethrow only an unexpected error. An expected failure (an `ExpectedException`: wrong credentials,
  a value the server rejected) sets the `error` state and is not rethrown, so the observer and the
  crash reporter see only bugs and outages. See "Expected and unexpected errors".
- `SequentialControllerHandler` for load/watch and pagination.
  `DroppableControllerHandler` for mutations (create, save, delete). Every controller picks one:
  without a handler its calls run at the same time and race on its state. See "One queue per
  controller".
- A controller is a business logic component behind publish/subscribe: it knows nothing of the
  widgets, is not one big store per screen, and its states hold the feature's own models only. See
  "What a controller is".
- One controller, one domain concern. Split when the async parts need different handlers or have
  independent `processing`/`error` state. A controller with four repositories, or with one method
  per setting, is a super-controller: split it by concern, and save a settings screen with one
  call that takes the whole settings model.
- A state is a case of its sealed class, never one big class of fields and flags: build the next
  state from its case (`XState.processing(data: state.data)`), never with `state.copyWith(...)`. A
  single class with flags is what makes every reader check whether its data is valid. `copyWith`
  on the data model inside the state is fine.
- Filters, switches and checkboxes are synchronous and cannot fail: they are no controller's
  business. Keep them in `ValueNotifier`s (or the data controller) and reload on their change; see
  "Filters and reloading". State that dies with its widget is ephemeral and never gets a
  controller; see "Ephemeral and application state".
- Controllers of one feature never import each other. Widgets coordinate them with a listener
  method (`addListener(_onCall)`) or the `listener` of `StateConsumer`, and react to a transition
  (`oldState`, `newState`), not to a state. See "Coordination rule".
- A controller keeps no query or filter field. The widget passes the filter on every call.
- Its private fields are what its constructor received (repositories, settings) and its stream
  subscriptions; the data lives in the state. Each new state carries the data on, copied even when it did not change. New state and
  model objects are cheap: the garbage collector is built for many short-lived objects, the same
  way every rebuild creates new widgets.
- Its public surface is its methods (the calls in) and `state` (the state out): no public fields,
  setters or getters of its own. What `control` exposes (`isProcessing`) is fine; a convenience
  getter goes on the state. It learns things only from the arguments of its methods and from the
  repositories its constructor received.
- Nothing from the controller down (controllers, repositories, data providers, models) imports
  Flutter's UI: no `material.dart` or `widgets.dart`, no `BuildContext`, widgets or `Color`.
  `package:flutter/foundation.dart` (`ChangeNotifier`, `@immutable`), which `control` builds on, is
  the exception.
- Never save states to restore them later (`hydrated_bloc` and the like): a restored `processing`
  or `successful` means nothing. Save what must survive a restart through a repository (drift or
  `shared_preferences`) and load it when the app starts.
- Dialogs with an async action: `PopScope(canPop: state is! ...ProcessingState)`.
- Read a freezed state with a `switch` over its sealed cases (or a getter on the state), not with
  the generated `when` / `map` / `maybeWhen`: Dart's own pattern matching is exhaustive and needs
  nothing generated. Freezed stays for `==`, `hashCode`, `copyWith` and `toString`.
- Test a controller through its states (`controller.toStream()` and `emitsInOrder`), not with
  `bloc_test`: see "Testing a controller".
- A screen's controller is created synchronously in `initState` (or right before opening a modal)
  and starts loading at once; the screen never waits for a controller to be built. See "Creating a
  controller for a screen".

## What a controller is

A controller (the BLoC idea: Business Logic Component) separates the widgets from the data with the
publish/subscribe pattern: widgets call its methods (sinks in) and listen to its state (streams
out); the controller publishes changes and does not know who listens. That loose coupling is the
point, together with a predictable order in which calls turn into states, and errors that stay in
the controller (its observer) instead of reaching widgets.

What a controller is not:

- **Not a function from a call to a state.** One call can produce zero, one or many state changes,
  and end in the same state or a different one.
- **Not a ViewModel or a Presenter.** It knows nothing about the view; the widgets know the
  controller and adapt what it publishes for themselves.
- **Not the storage of one screen.** "One controller per screen holding every state" is wrong: a
  controller is one component with one concern, and a screen may use several.
- **Not centralized state.** Unlike Redux or TEA there is no single store; there are many small
  controllers, each for its purpose.
- **Not tied to an implementation.** It works with repository interfaces, and its states never
  expose database rows, generated classes or DTOs: only the feature's own models.
- **Not part of the widgets.** It lives in the feature's `controller/` folder, never in `widgets/`,
  even though what it publishes changes what the widgets show: the widgets depend on it, not the
  other way round.

## Ephemeral and application state

- **Ephemeral state** belongs to one widget and dies with it: a text field's value, the selected
  tab, an animation's progress, an expanded tile, a list filtered on the client. It lives in the
  widget's `State` (`setState`), a `ValueNotifier` or a data controller under `widgets/controllers/`.
  It never gets a `StateController`: nothing in it is asynchronous or can fail.
- **Application state** is read by other parts of the app, outlives the screen, or comes from or
  goes to a repository: the signed-in user, the products from the server, the theme and language.
  It lives in a controller (a screen's, or an app-wide one in `Dependencies`) and, when it must
  survive a restart, in a repository.
- Ephemeral state grows into application state: a list filtered in the widget becomes a server
  query. When that happens, the call moves into the controller and the filter stays in the widget,
  passed on every call (see "Filters and reloading").
- A controller never holds a widget's detail (a tab index, a scroll offset) so that another widget
  can change it. When a button in one part of the screen must change another part (switch to the
  posts tab and filter it), it takes a callback; the widget that owns both parts implements it:
  `setState(() => _tab = 0)` for its own state, then `postsController.load(userId: id)`.

## Other state management packages

A project that already uses one of these keeps it: rewriting a working app's state layer is not
part of a feature. New code follows the project's package, with the rules below.

- **`bloc`**: the same idea as a controller (events in, states out, `BlocObserver`). The cost is
  the learning curve, and blocs that depend on each other are awkward to wire. Events are not
  queued by default: every `on<E>` runs concurrently with the others, so use one handler with
  `sequential()` (see "One queue per controller"). A global `Bloc.transformer = sequential()` does
  not give a bloc one queue: the default is applied to each `on<E>` separately, over the events of
  that type only, so different event types still overlap on the shared state (checked: `bloc`
  9.2.1). After its first `emit`, a bloc drops a state
  that is `==` to the current one: no `onChange`, no `onTransition`, no observer call, no rebuild
  (checked: `bloc` 9.2.1, `if (state == _state && _emitted) return;`). With freezed states that is
  equality by value, so emitting the same `processing(data: x)` twice is one state, and re-emitting
  a state never fires a listener again. `control` does not filter: every `setState` calls the
  observer and notifies, so `toStream()` emits equal states twice; `StateConsumer` skips only an
  `identical` state (checked: `control` at the pinned commit).
- **`Cubit`**: methods instead of events, so no queue: overlapping calls race. Only for controllers
  whose states come from a stream (see "Publishers and subscribers").
- **`ChangeNotifier` alone**: enough for an MVP or a small app; nothing to learn beyond Flutter.
  There is no queue and no observer, so ordering calls and reporting errors are up to you.
- **Redux**: one global store. It fits a small app with few unrelated features, and gets in the way
  once features have their own multi-step processes.
- **MobX**: observables tracked implicitly through code generation; what rebuilds when is hard to
  see, and extra rebuilds are easy to cause.
- **Riverpod, `get_it`**: global variables with extra steps. In a project that keeps Riverpod, a
  provider gets its repository through a provider that tests override
  (`ProviderContainer(overrides: [repositoryProvider.overrideWithValue(fake)])`), and never
  `ref.watch`es another feature's provider: the products provider failing because the user
  provider failed couples two features, errors included. Connect them in the widget, as with
  controllers. How long a provider lives (`keepAlive`) is decided by the widget that owns the
  screen, as with a config widget, not inside the provider. And one package that is the state
  management, the dependency injection and the local cache at once cannot be replaced one
  concern at a time. Riverpod 3 retries a failing provider by itself: the default
  (`ProviderContainer.defaultRetry`) retries any `Exception` up to 10 times, from 200 ms doubling
  to 6.4 s, and does not retry an `Error` or a `ProviderException`. A request the server rejected
  is sent again and again, and the screen shows loading meanwhile: set `retry:` on the root
  `ProviderScope` (or the provider) to a function that returns `null` for the app's expected
  exceptions, and never make a non-idempotent call in a provider's `build`. Reading a failed
  provider's value (`requireValue`, or a provider that reads another one that threw) throws a
  `ProviderException` wrapping the error, so `on ExpectedException catch` there never matches;
  `await ref.watch(p.future)` and `AsyncValue.error` give the original (checked: `riverpod`
  3.4.3); **`provider`**: a wrapper around
  `InheritedWidget` for passing dependencies, not state management. See `docs/rules/dependencies.md`.
- **Elementary**: a widget–view model pair per screen (MVVM); a controller is not a view model (see
  "What a controller is").
- **Stacked**: an MVVM framework that registers services in `get_it` and also hands them down with
  `provider`: a service locator and a second DI path at once, and a view model per view, not a
  controller per concern. Its `NavigationService` and `DialogService` open UI from anywhere (see
  "No navigator key outside the widgets" in `docs/rules/navigation.md`).
- **GetX**: no. It mixes state, navigation and dependencies behind globals.
- **An event bus** (one app-wide stream everyone posts to and listens on): adding features is easy,
  but nobody can see who reacts to what. Connect controllers through the widget or a repository's
  stream instead (see "Multiple controllers in one feature").

## Publishers and subscribers

The publish/subscribe roles around a controller:

- **Publisher**: whatever asks the controller to act: a widget calling `controller.load()` on a
  tap, a listener, another controller's reaction. In the `bloc` package this is `bloc.add(Event())`.
- **Subscriber**: whatever listens to its state: a `StateConsumer` or `ListenableBuilder` that
  rebuilds, a listener that shows a SnackBar or navigates.

- The states are not tied to the calls that caused them: a subscriber sees `processing` or
  `successful` without knowing, or caring, which call or how many calls produced it.
- Widgets are not the presentation layer either: they are the configuration of the UI. The
  controller is in neither; its only links to them are the calls in and the state out.
- A controller that is just methods setting state (a bloc `Cubit`) has no queue: two calls overlap
  and race, and a call cannot be dropped or put in order. That is what the concurrency handlers
  are for: every `control` method goes through `handle`, and the handler queues or drops it (see
  "One queue per controller").
- The exception: a controller (or `Cubit`) with no public methods, whose states come from a stream
  of the outside world: a web socket, the location, the connection, the battery. Nothing calls it,
  so nothing can race.
- Search as you type: wait for typing to pause (a `Timer` of about 300 ms in the widget's data
  controller) before calling `search(query)`, and let the controller drop an answer whose query is
  no longer the current one, so a slow old response never replaces a newer list.

### Observer, publish/subscribe and a state machine

Three patterns meet in a controller; they are easy to confuse:

- **Observer.** The subject keeps the list of its listeners and calls each of them, one after
  another, synchronously, when it changes. A listener gets no value: it reads the subject. This is
  `Listenable` and `ChangeNotifier` (`notifyListeners()`); `ListenableBuilder` and `StateConsumer`
  are such listeners, added with `addListener` while they are mounted. The subject knows its
  subscribers, as callbacks.
- **Publish/subscribe.** Publishers and subscribers do not know each other; a channel sits between
  them. In `bloc`, `add(event)` puts an event into the bloc's stream, where events can wait in a
  queue, run in order, be dropped or debounced; states leave through another stream, and the bloc
  never knows who listens. Events and states are not one to one.
- **State machine.** The states are a fixed set (`idle`, `processing`, `successful`, `error`), and
  every change is a transition from one to another. The controller observer (`Controller.observer`'s
  `onStateChanged`, or `BlocObserver` in `bloc`) sees every transition: one place to log and report.

A `control` controller is all three: a `ChangeNotifier` that widgets observe (and `toStream()` for
stream subscribers), calls that go through `handle` and its concurrency handler like events through
a channel, and freezed states with transitions the observer sees.

## One queue per controller

Asynchronous calls that overlap cause race conditions: floating bugs that are hard to see, trace or
reproduce. A controller exists to prevent them, by putting every call through one queue:

- **Drop while busy** (`DroppableControllerHandler`): a character that jumped cannot jump again in
  the air; a second sign-in tap while signing in does nothing. Mutations whose repeat is a mistake:
  save, delete, sign in, pay.
- **Run in order** (`SequentialControllerHandler`): `update('John'); update('Ann'); update('Elon');`
  reaches the server in that order, so the last call wins, predictably. Loading, watching,
  pagination, and any update whose calls must all apply.
- **Never at once.** Without a handler, `control` runs the calls concurrently; on shared state,
  that is the race this section is about. Signing in as user #1, as user #2 and signing out at the
  same time must be impossible.

The queue is per controller, across all its methods: `load()` and `paginate()` of one sequential
controller never interleave, because every `handle` waits for the same lock.

A project that uses the `bloc` package has to get this right by hand: every `on<E>(...)` subscribes
to the event stream with its own queue, so `on<Increment>` and `on<Decrement>` each keep their own
order but run over each other on the shared state, and a `sequential()` transformer on each `on`
does not change that. Register one handler for a sealed event type and switch inside it, with one
transformer (`sequential()` from `bloc_concurrency`):

```dart
on<CounterEvent>(
  (event, emit) => switch (event) {
    Increment() => _increment(emit),
    Decrement() => _decrement(emit),
  },
  transformer: sequential(),
);
```

## One recipe for states

Almost every controller action is the same few lines. The data travels through all four states;
only the variant tells what is happening now:

```dart
@freezed
sealed class AuthState with _$AuthState {
  const AuthState._();

  /// Nothing is running.
  const factory AuthState.idle({required User user}) = Auth$IdleState;

  /// An action is running; [user] is still what the screen shows.
  const factory AuthState.processing({required User user}) = Auth$ProcessingState;

  /// The action finished; [user] is its result.
  const factory AuthState.successful({required User user}) = Auth$SuccessfulState;

  /// The action failed; [user] is unchanged.
  const factory AuthState.error({required User user, required Object error}) = Auth$ErrorState;

  /// A flag is a getter over the data, not a state of its own.
  bool get isAuthenticated => user is AuthenticatedUser;
}

void signIn(String login, String password) => handle(() async {
  setState(AuthState.processing(user: state.user));
  try {
    final user = await _repository.signIn(login, password);
    setState(AuthState.successful(user: user));
  } on Object catch (error) {
    setState(AuthState.error(user: state.user, error: error));
    // A wrong password is an answer, not a bug. Anything else: `handle` reports it to the
    // controller observer (the log and the crash reporter).
    if (error is! ExpectedException) rethrow;
  } finally {
    setState(AuthState.idle(user: state.user));
  }
});
```

- A field declared in every variant (`user`, `data`) is on the union itself: `state.user` works in
  any state, so there is no `switch` just to read the data.
- Adding `signOut` or `refresh` adds no state: it is the same recipe with another repository call.
- A state per event (`loginProgress`, `authenticated`, `notAuthenticated`, `error`) multiplies with
  every new event; the four states do not.
- Several values travel together as one data class (`ProductsData` in the paginated example), not as
  separate fields of every variant.
- An action without data (a deletion) uses the same four states without the data field.
- An error that must stay on screen (a first load that failed, shown in place of the list with a
  retry) is part of the data, not a state: `ProductsData.error`, set in the `catch` and cleared by
  the next successful load, which builds fresh data. The `error` state still passes for the
  listener (a SnackBar for a failed page); the `idle` state that follows keeps the error in its
  data, and the builder shows the error view while there are no rows (see
  `products_controller.dart` and `products_list_widget.dart`).

### Cached data first, then fresh

`processing` carries data too, so one action can show what it has while it is still working: the
saved copy at once, the server's answer when it arrives.

```dart
void load() => handle(() async {
  setState(ProductsState.processing(data: state.data));
  try {
    final cached = await _repository.cachedProducts(); // the local database: fast
    setState(ProductsState.processing(data: cached));
    final fresh = await _repository.fetchProducts(); // the server; the repository saves it
    setState(ProductsState.successful(data: fresh));
  } on Object catch (error) {
    setState(ProductsState.error(data: state.data, error: error));
    if (error is! ExpectedException) rethrow;
  } finally {
    setState(ProductsState.idle(data: state.data));
  }
});
```

- The screen shows the cached list while a small progress indicator says that more is coming;
  it never waits on the network to show something.
- If the server fails, `error` and then `idle` keep the cached list: the user loses nothing.
- Each `setState` is a new state with the current data; the data is never patched in place.
- The cache and the server are two repository methods, and the controller chooses the order and
  what a failure of the second one leaves on screen (see "What the repository does" in
  `docs/rules/architecture.md`).

### Optimistic update

An edit the server almost always accepts (a rename, a like, a toggle) shows the new value at once,
in `processing`, and rolls back if the server refuses:

```dart
void rename(String name) => handle(() async {
  final previous = state.profile;
  setState(ProfileState.processing(profile: previous.copyWith(name: name)));
  try {
    final saved = await _repository.update(previous.copyWith(name: name));
    setState(ProfileState.successful(profile: saved));
  } on Object catch (error) {
    setState(ProfileState.error(profile: previous, error: error)); // the rollback
    if (error is! ExpectedException) rethrow;
  } finally {
    setState(ProfileState.idle(profile: state.profile));
  }
});
```

- Keep the previous data in a local variable before the first `setState`; `error` carries it, so
  the screen shows the old value again, and `idle` follows with whatever the last state had (the
  saved profile, or the old one). Checked by a test: `processing` has the new name, `error` and
  `idle` the old one.
- `successful` carries what the server returned, not the optimistic value: the server may
  normalise it (trim, lowercase).
- The listener shows the failure (a SnackBar): a value that silently jumps back reads as a glitch.
- `Droppable` for a single save button. When every call must apply in order (a like tapped twice),
  use `Sequential`, and build each call from `state`, which holds the previous call's result.

### Where the rethrown error goes

The `rethrow` does not crash anything and does not reach the widget:

- `handle` runs the action inside a guarded zone and catches what it throws. It always passes the
  error to `Controller.observer`'s `onError`, and the `Future` of the call completes normally (with
  `null`), so the caller has nothing to catch. In `bloc`, `BlocObserver.onError` plays the same role.
- The optional `error:` callback of `handle` runs after the observer, not instead of it: it cannot
  keep an error out of the log. Only the action itself can, by catching and not rethrowing (see
  "Expected and unexpected errors"). Checked in the pinned `control` source and by a test.
- The widget learns about the failure from the `error` state, not from an exception.
- Set `Controller.observer` once at startup to an observer that logs and reports to the crash
  reporter; without one, the rethrown error is reported nowhere.
- Await every `Future` inside `handle`. An unawaited one that fails escapes the `try` and lands in
  the zone's handler, which also reports it but asserts in debug mode: the assert points at the
  missing `await`.

### Expected and unexpected errors

Not every failure is a bug. A wrong password, a taken email or a value the server rejected is the
feature's answer: the user reads it and acts. A failed parse, a `StateError`, a server 500 or a
lost connection (`APIClientException$Network`) is not the answer the feature promises: someone has
to look at it. The observer (and the crash reporter behind it) is for the second kind only; filled
with the first, it hides the bugs among thousands of mistyped passwords.

- The data layer marks the expected kind when it translates an error at the boundary (see "Errors"
  in `docs/rules/repositories.md`): it throws a subtype of `ExpectedException`
  (`app_exception.dart` below), such as `RejectedException(code: 'wrong_password')`. Whether a
  failure is an answer is known where the server's code is read, so it is decided there once.
- The action sets the `error` state for every error, and rethrows only what is not an
  `ExpectedException`: `if (error is! ExpectedException) rethrow;`. The screen shows both kinds the
  same way, through `errorText`; only the unexpected kind reaches `Controller.observer.onError`.
  Checked by a test: an `ExpectedException` gives processing, error, idle and no observer call; a
  `StateError` gives the same states and one observer call.
- A lost connection (`APIClientException$Network`) is reported too: it is not a bug, but how often
  it happens is worth knowing. The observer may log it at a lower level by its type.
- An expired session (`APIClientException$Authorization`) is the authentication middleware's: it
  refreshes the token, or signs the user out (see "HTTP middleware" in
  `docs/rules/dependencies.md`). The controller sets `error` and rethrows it like any other, and
  the crash reporter leaves it out: once a reporter is added, `$captureException`
  (`lib/src/_core/utils/error_util/platform/` in a new project) returns early for it.
- Never catch `on Object` without the rethrow line: that silences every bug of the action.
- With `bloc`, the same split: for an `ExpectedException` emit the error state and return; let
  everything else reach `onError` (`BlocObserver.onError`).

## Testing a controller

A controller is tested by the sequence of its states. `toStream()` emits every state change from the
moment it is called (not the current state) and buffers them until the test listens; `dispose`
closes it. No `bloc_test`-style package is needed: the matchers of `package:test` say more.

```dart
test('signIn goes processing, successful, idle with the signed-in user', () async {
  final controller = AuthController(repository: FakeAuthRepository(user: ann));
  addTearDown(controller.dispose);
  final states = controller.toStream();

  controller.signIn('ann', 'secret');

  await expectLater(
    states,
    emitsInOrder(<Matcher>[
      isA<Auth$ProcessingState>(),
      isA<Auth$SuccessfulState>().having((s) => s.user, 'user', ann),
      isA<Auth$IdleState>().having((s) => s.isAuthenticated, 'isAuthenticated', isTrue),
    ]),
  );
});

test('a failed signIn keeps the old user and goes back to idle', () async {
  final controller = AuthController(repository: FakeAuthRepository(error: StateError('offline')));
  addTearDown(controller.dispose);
  final states = controller.toStream();

  controller.signIn('ann', 'wrong');

  await expectLater(
    states,
    emitsInOrder(<Matcher>[
      isA<Auth$ProcessingState>(),
      isA<Auth$ErrorState>().having((s) => s.error, 'error', isStateError),
      isA<Auth$IdleState>().having((s) => s.isAuthenticated, 'isAuthenticated', isFalse),
    ]),
  );
});
```

- `isA<T>().having(feature, description, matcher)` checks one part of a state; nest matchers
  (`allOf`, `isNotEmpty`, `equals`) for lists and records.
- Stub the repository with `mocktail` per test (`docs/rules/testing.md`); never mock the
  controller.
- Controllers with timers (debounce, polling) run inside `fakeAsync`: see `docs/rules/testing.md`.
- To check what is reported, set `Controller.observer` to a fake that records `onError` calls and
  put the old one back with `addTearDown`; count after the `emitsInOrder` expectation has seen
  `idle`, then `await pumpEventQueue()` (the report runs after the action's last state). An
  expected failure leaves the list empty.
- With `bloc`, `bloc.stream` is a broadcast stream that does not buffer: states emitted before the
  test listens are lost. Start the expectation first, act, then await it:
  `final expectation = expectLater(cubit.stream, emitsInOrder([...])); cubit.save(...); await
  expectation;`. A helper that hides this behind a `Completer` completed in `whenComplete` returns
  normally even when the sequence is wrong, and the lines after it run on the wrong state; await
  the expectation itself.

## Creating a controller for a screen

A controller is built synchronously and loads in the background: the screen opens at once and
shows `processing`, then `idle` with the data. Nothing is awaited before the screen appears.

In a config widget, create it in `initState` and start the load there:

```dart
late final ProductsController _controller;

@override
void initState() {
  super.initState();
  _controller = ProductsController(
    productsRepository: DependenciesScope.of(context).productsRepository,
  )..load();
}

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}
```

For a modal route (a search, a sheet), build the controller where the route opens, hand it to the
route, and dispose it when the route closes, however it closes:

```dart
void openSearch(BuildContext context) {
  final controller = ProductSearchController(
    repository: DependenciesScope.of(context).productsRepository,
  )..load();
  showSearch<void>(
    context: context,
    delegate: ProductSearchDelegate(controller: controller),
  ).whenComplete(controller.dispose).ignore();
}
```

- The function that opens a screen is not `async`: the user taps and the screen appears.
  `await`ing a factory first leaves them looking at the old screen with nothing happening.
- `whenComplete` disposes the controller whether the route completed or failed, and `.ignore()`
  keeps an error out of the widget: opening a route must not fail, and a controller's own errors
  go to its observer through `handle`, never to the widget that opened it.
- `async` / `await` with `close()` after it is the bug this replaces: when `showSearch` throws, or the
  `context.mounted` check returns early, the controller is never disposed.
- Passing a controller to the route through its constructor is fine: the route does not own it,
  the code that opened the route does.

## Controller patterns

### Single responsibility

Every feature folder and every controller has one domain responsibility. A responsibility is not a
single function; it is a single domain concern.

A controller may have several methods when they serve the same concern. An
`AuthenticationController` with `signIn`, `signOut` and `checkToken` is fine: all three answer "is
this user authenticated?". Splitting them into three features is over-engineering.

Split when two things have genuinely independent UI state machines or no logical connection at the
domain level. Quick replies are three features:

```
example_list/       "provide the reactive list to the UI"
example_creation/   "manage the create/edit form lifecycle (processing, successful, error)"
example_deletion/   "manage the delete confirmation lifecycle (processing, successful, error)"
```

The creation form and the deletion dialog each need their own `processing` / `successful` / `error`.
If they shared one controller, a deletion in progress could overwrite the form's state and break
`PopScope`. The list (watching a stream) has no state overlap with either mutation.

### Mutation features (creation, deletion)

```
feature_name/
├── data/feature_name_repository.dart       (interface + impl)
├── controller/feature_name_controller.dart (freezed states + handle())
└── widgets/
    ├── feature_name_config_widget.dart     (InheritedWidget scope + static factory)
    └── feature_name_dialog_widget.dart     (form / confirmation UI)
```

The controller uses `DroppableControllerHandler`, so duplicate taps are dropped. Templates:
`example_creation_controller.dart`, `example_deletion_controller.dart` and their repository
interfaces in `example_mutation_repositories.dart` (in Examples below; adjust the imports to the layout):

```dart
class ExampleCreationController extends StateController<ExampleCreationState>
    with DroppableControllerHandler {
  void save({required String title, required String content, Example? existing}) =>
      handle(() async {
        setState(ExampleCreationState.processing(example: state.example));
        try {
          final saved = await _repo.save(title: title, content: content, existing: existing);
          setState(ExampleCreationState.successful(example: saved));
        } on Object catch (error) {
          setState(ExampleCreationState.error(example: state.example, error: error));
          if (error is! ExpectedException) rethrow;
        } finally {
          setState(ExampleCreationState.idle(example: state.example));
        }
      });
}
```

Use `SequentialControllerHandler` for load/watch.

The config widget owns the controller lifecycle and exposes a static factory so callers need one
line:

```dart
class ExampleCreationConfigWidget extends StatefulWidget {
  static Future<void> showCreationDialog(BuildContext context, {Example? existing}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ExampleCreationConfigWidget(
        builder: (_) => ExampleCreationDialogWidget(existing: existing),
      ),
    );
  }
  // ...
}
```

The dialog widget closes itself with `StateConsumer` and blocks dismissal mid-flight with
`PopScope` (`example_deletion_dialog.dart`):

```dart
StateConsumer<ExampleCreationController, ExampleCreationState>(
  controller: _controller,
  listener: (context, controller, oldState, newState) {
    if (newState is ExampleCreation$SuccessfulState) Navigator.pop(context);
  },
  builder: (context, state, child) => PopScope(
    canPop: state is! ExampleCreation$ProcessingState,
    child: AlertDialog(...),
  ),
);
```

The calling site only uses the factory:

```dart
ExampleCreationConfigWidget.showCreationDialog(context);
ExampleCreationConfigWidget.showCreationDialog(context, existing: example);
ExampleDeletionConfigWidget.showDeletionDialog(context, example);
```

### Rules

- Group by domain concern, not by function count.
- Create and update may share one feature when they write the same record. The create-vs-update
  decision belongs in the repository, not the controller or widget.
- Split when UI states are independent: if two operations each show their own
  `processing` / `successful` / `error` at once or to different widgets, they need separate
  controllers and features.
- Config widgets own the controller lifecycle: created in `initState`, disposed in `dispose`,
  nowhere else.
- Static factory methods on config widgets keep wiring internal and give callers a one-line API.
- `DroppableControllerHandler` for mutations, `SequentialControllerHandler` for load/watch.
- `PopScope(canPop: state is! ...ProcessingState)` on every dialog with an async operation.

### Filters and reloading

The widget owns its filters, merges them into one `Listenable`, and asks the controller to reload
when any of them changes:

```dart
final ValueNotifier<SortOrder> _sort = ValueNotifier<SortOrder>(SortOrder.newest);
final ValueNotifier<bool> _inStock = ValueNotifier<bool>(false);
late final Listenable _filters = Listenable.merge(<Listenable>[_sort, _inStock]);

@override
void initState() {
  super.initState();
  _filters.addListener(_reload);
  _reload();
}

void _reload() => _controller.load(sort: _sort.value, inStockOnly: _inStock.value);

@override
void dispose() {
  _filters.removeListener(_reload);
  _sort.dispose();
  _inStock.dispose();
  super.dispose();
}
```

`Listenable.merge` adds the listener to each notifier and removes it from each; it owns nothing,
so the notifiers are still disposed one by one.

### Multiple controllers in one feature

Split a feature's controllers when its async operations either need different concurrency handlers
(`Droppable` vs `Sequential`) or keep independent state that must update simultaneously without one
overwriting the other.

```
call/controller/
├── call_controller.dart
├── call_media_controller.dart
└── call_members_controller.dart
```

Business logic components do not depend on each other: the layer above (the widgets) or below
(a repository) connects them. A controller that picks a photo does not get the user controller to
update the avatar; tomorrow it would also get analytics, and every controller would know half the
app. The widget takes the photo from the first controller's `successful` state and passes the photo
to the second: `userController.updateAvatar(photo)`.

When one controller depends on the state of another, there are two ways, and a controller never
receives another controller:

1. **Through the widget.** The widget listens to the first (`addListener`, the `listener` of
   `StateConsumer`) and calls the second.
2. **Through the repository.** The first writes through a repository; the second watches a
   `Stream` of the same repository and updates itself (see "Single source of truth" in
   `docs/rules/architecture.md`).

Each handles one async concern. `CallMediaController` is `Droppable`, so rapid taps are dropped.
`CallController` is `Sequential`, so join and leave never interleave. One shared controller would
force a single strategy on all three.

#### Coordination rule

Controllers in the same feature never import or depend on each other. The widget layer coordinates
them with a listener method or the `listener` of `StateConsumer`: it reacts to one controller's
change and calls methods on another. The config widget that created the three controllers:

```dart
@override
void initState() {
  super.initState();
  // ... the three controllers are created here.
  _wasInCall = _callController.state.inCall;
  _callController.addListener(_onCall); // a method, so it can be removed (widgets.md)
}

/// Resets members and media once, when the call ends: on the transition, not on every
/// notification while there is no call.
void _onCall() {
  final inCall = _callController.state.inCall;
  if (_wasInCall && !inCall) {
    _callMembersController.reset();
    _callMediaController.reset();
  }
  _wasInCall = inCall;
}

@override
void dispose() {
  // Created here, so disposed here; dispose drops `_onCall` with the other listeners.
  _callController.dispose();
  _callMembersController.dispose();
  _callMediaController.dispose();
  super.dispose();
}
```

- Listen with a method, never a closure: see "Listeners and dispose" in `docs/rules/widgets.md`.
  A listener on a controller the widget did not create is removed in `dispose`.
- React to a transition, not to a state. Every action of the four-state recipe ends in `idle`, and
  a controller notifies on every `setState`, so `if (state is Call$IdleState)` runs after every
  action, not once. Compare the previous and the current value: a field the listener updates (as
  `_wasInCall` above), or the `oldState` and `newState` that `StateConsumer`'s `listener` receives.
- The listener forwards the fact; the controller decides whether it matters. `reset()` on a
  controller with nothing to reset does nothing; the widget does not check that for it.

#### Coordinating app-wide controllers

Two app-wide controllers (authentication and the cart, both built at startup in `Dependencies`)
have no config widget to connect them. A small widget placed once above the screens (in
`MaterialApp.builder`, or around the app's root) does it, and returns its child unchanged:

```dart
/// Loads the cart when the user signs in, and clears it when they sign out.
class AuthCartSync extends StatelessWidget {
  const AuthCartSync({super.key, required this.auth, required this.cart, required this.child});

  final AuthController auth;
  final CartController cart;
  final Widget child;

  @override
  Widget build(BuildContext context) => StateConsumer<AuthController, AuthState>(
    controller: auth,
    listener: (context, controller, oldState, newState) {
      if (!oldState.isAuthenticated && newState.isAuthenticated) cart.load();
      if (oldState.isAuthenticated && !newState.isAuthenticated) cart.clear();
    },
    buildWhen: (_, _) => false, // nothing to rebuild: it only listens
    child: child,
  );
}
```

- `StateConsumer` with no `builder` returns its `child`, and `buildWhen` returning `false` keeps it
  from rebuilding on every state; it adds and removes its listener itself.
- The check is on the transition (`!old && new`): the auth controller passes `processing`,
  `successful` and `idle` while signed in (a token refresh, a profile reload), and a plain
  `newState.isAuthenticated` would reload the cart on each of them. Checked by a widget test: one
  `load` on sign-in, none on a later authenticated-to-authenticated action.
- The controllers come in through the constructor (from `DependenciesScope.of(context)` where it
  is placed), not read inside the listener.

## Paginated controllers

Every paged list follows one shape. Copy it rather than inventing a variant: the differences
between hand-rolled paginators are where the silent bugs live.

### Rules

1. **The cursor lives in the state, never in a controller field.** `page` and `hasMore` are fields
   of the data every state carries (`ProductsData`). A mutable `int _page` on the controller can be
   advanced past a page that failed, which leaves a permanent, invisible hole in the list.
2. **Everything the controller depends on arrives through the constructor**: repository, page size,
   pagination util, initial filter. A dependency built inside the controller cannot be substituted
   in a test or varied per screen.
3. **`page` in the data is the next page to request**, not the one just loaded.
   `LocalPaginationUtil.checkIsListHasMorePageInt` computes it. The util lives at
   `lib/src/_core/utils/local_pagination_util.dart` and infers "has more" from page fullness: a full
   page (length == `limitInPage`) means another page probably exists, a short page means the end. No
   server `total` is required; keep `total` in the state only when the UI shows a count.
4. **Two methods, never one.** `load(...)` fetches page 1 and resets the state; `paginate(...)`
   appends the next page. Both run through the same `SequentialControllerHandler`, so they never
   interleave and a second page request arriving mid-flight runs instead of being dropped. Never
   `Droppable` here: a `load` for a new filter or a pull-to-refresh that arrives while a page is
   loading would be dropped, and the list would keep the old filter's rows with nothing telling
   the user. Sequential runs it after the page, and its fresh page 1 replaces the rows. (The
   `hasMore` guard and the widget's `isProcessing` check keep repeated scroll events from queueing
   pages.)
5. **The async controller stays query-stateless.** No `_query`, `_from`, `_storeUid` fields. The
   active query and filters live in a `ChangeNotifier` data controller under `widgets/controllers/`;
   the config widget reads them and passes them to `load(...)` / `paginate(...)` on every call.
   App-global scope values such as `store_uid` are not passed at all: the repository reads them.
   Echoing the active query in the data is a display concern and fine; storing it as a mutable
   controller field is not.

### Template

`products_controller.dart` (state, `load`, `paginate`), `products_repository.dart` (returns the page
and the server total as a record, `typedef ProductsPage = (List<Product> products, int total)`),
`local_pagination_util.dart`, `product.dart`, `products_data_controller.dart`,
`products_list_widget.dart`. `paginate`'s `hasMore` guard is what makes the repeated firing of a
bottom-of-list scroll notification safe.

### Convenience getters on the state

Put shared accessors on the sealed state, not the controller (`allCustomers`, `selectableCustomers`).
Add `const XxxState._();` to the union so it can carry methods. Every variant carries the same data
field, so a getter just reads it:

```dart
List<Product> get products => data.products;
bool get hasMore => data.hasMore;
```

Give a getter a different name from the data's fields when it computes across them
(`allCustomers` reads `customers`).

### Triggering `paginate` from the widget

The widget fires `paginate()` from a `ScrollController` near the bottom of the list, guarded by
`controller.isProcessing` (exposed by `SequentialControllerHandler`) so a burst of scroll
notifications starts one fetch. Show a footer spinner while `hasMore`.

The filter lives in the data controller; the config widget owns both controllers and passes the
filter on every call:

```dart
// widgets/controllers/example_data_controller.dart
class ExampleDataController with ChangeNotifier {
  int? _filterId;
  int? get filterId => _filterId;
  void setFilter(int? value) {
    if (_filterId == value) return;
    _filterId = value;
    notifyListeners();
  }
}

// example_config_widget.dart
void load()     => controller.load(filterId: dataController.filterId);
void loadMore() => controller.paginate(filterId: dataController.filterId);
```

### Non-paginated lists

An endpoint that truly returns one fixed or capped list (a small summary feed, a hard top-N with no
page controls) does not use this pattern: fetch it in one `load()` and render it, with no
`paginate()`. When in doubt, add pagination; most list endpoints accept `page` / `page_size`.

### Refinements, where the screen earns them

- **The rows stay through everything.** `load` and `paginate` both set `processing` with the
  current data, so the list stays on screen while a page loads; show the spinner only when there
  are no rows yet. A screen that must blank on a new search passes `const ProductsData()` instead.
- **A failed page keeps the rows and the cursor.** `error` carries the data unchanged, so the same
  page is requested again on the next scroll or from the retry the listener shows. The listener
  must show the failure: a list that silently stops growing reads as the whole list.
- **Appended pages are deduplicated by id.** Offset pages of a list that changes while the user
  scrolls overlap: a row added on the server pushes the last row of page 1 onto page 2, and it
  arrives twice. `paginate` merges by id (`_append` in `products_controller.dart`): a row already
  shown is replaced where it stands by its newer copy, new ids are added at the end. Do not
  `sort()` the merged list unless the screen's order differs from the server's. A cursor-based
  API (`after: lastId`) does not overlap; dedupe anyway, it costs one map.
- **Echo the active filter/query in the data** when the app bar must show how many facets are on.
  The controller still takes the initial one through its constructor.

## Examples

Whole files, one per block; put each where the layout above says and adjust the imports.

### `app_exception.dart`

```dart
// file: app_exception.dart
/// A failure the feature expects as an answer, not a bug: the user can read it and act. The data
/// layer throws a subtype at the boundary; a controller sets its `error` state and does not
/// rethrow it, so the observer and the crash reporter never see it. Lives in
/// `lib/src/_core/model/`.
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
```

### `example_creation_controller.dart`

```dart
// file: example_creation_controller.dart
import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'app_exception.dart';
import 'example.dart';
import 'example_mutation_repositories.dart';

part 'example_creation_controller.freezed.dart';

/// The form's states; each carries the example saved so far (`null` before the first save).
@freezed
sealed class ExampleCreationState with _$ExampleCreationState {
  const factory ExampleCreationState.idle({Example? example}) = ExampleCreation$IdleState;

  const factory ExampleCreationState.processing({Example? example}) =
      ExampleCreation$ProcessingState;

  const factory ExampleCreationState.successful({Example? example}) =
      ExampleCreation$SuccessfulState;

  const factory ExampleCreationState.error({Example? example, required Object error}) =
      ExampleCreation$ErrorState;
}

/// Saves the create/edit form. A mutation: [DroppableControllerHandler] drops a second tap while
/// the first save is running.
final class ExampleCreationController extends StateController<ExampleCreationState>
    with DroppableControllerHandler {
  ExampleCreationController({
    required this._repository,
    super.initialState = const ExampleCreationState.idle(),
  });

  final IExampleCreationRepository _repository;

  void save({required String title, required String content, Example? existing}) =>
      handle(() async {
        setState(ExampleCreationState.processing(example: state.example));
        try {
          final saved = await _repository.save(title: title, content: content, existing: existing);
          setState(ExampleCreationState.successful(example: saved));
        } on Object catch (error) {
          setState(ExampleCreationState.error(example: state.example, error: error));
          // A rejected value is an answer: shown, not reported. Anything else goes to the
          // controller observer through `handle`.
          if (error is! ExpectedException) rethrow;
        } finally {
          setState(ExampleCreationState.idle(example: state.example));
        }
      });
}
```

### `example_deletion_controller.dart`

```dart
// file: example_deletion_controller.dart
import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'app_exception.dart';
import 'example_mutation_repositories.dart';

part 'example_deletion_controller.freezed.dart';

/// The same four states; a deletion has no data to carry.
@freezed
sealed class ExampleDeletionState with _$ExampleDeletionState {
  const factory ExampleDeletionState.idle() = ExampleDeletion$IdleState;

  const factory ExampleDeletionState.processing() = ExampleDeletion$ProcessingState;

  const factory ExampleDeletionState.successful() = ExampleDeletion$SuccessfulState;

  const factory ExampleDeletionState.error({required Object error}) = ExampleDeletion$ErrorState;
}

/// Deletes one example. Its state is independent of the creation form, so it is its own
/// controller (and feature).
final class ExampleDeletionController extends StateController<ExampleDeletionState>
    with DroppableControllerHandler {
  ExampleDeletionController({
    required this._repository,
    super.initialState = const ExampleDeletionState.idle(),
  });

  final IExampleDeletionRepository _repository;

  void delete(int id) => handle(() async {
    setState(const ExampleDeletionState.processing());
    try {
      await _repository.delete(id);
      setState(const ExampleDeletionState.successful());
    } on Object catch (error) {
      setState(ExampleDeletionState.error(error: error));
      if (error is! ExpectedException) rethrow;
    } finally {
      setState(const ExampleDeletionState.idle());
    }
  });
}
```

### `example_deletion_dialog.dart`

```dart
// file: example_deletion_dialog.dart
import 'package:control/control.dart';
import 'package:flutter/material.dart';

import 'example_deletion_controller.dart';

/// Confirmation dialog. It closes itself on success and cannot be dismissed mid-flight.
class ExampleDeletionDialog extends StatelessWidget {
  const ExampleDeletionDialog({
    super.key,
    required this.controller,
    required this.exampleId,
    this.onSuccessfullyDelete,
  });

  final ExampleDeletionController controller;
  final int exampleId;

  /// Called before the dialog closes, so the parent screen can reload.
  final VoidCallback? onSuccessfullyDelete;

  @override
  Widget build(BuildContext context) {
    return StateConsumer<ExampleDeletionController, ExampleDeletionState>(
      controller: controller,
      listener: (context, controller, oldState, newState) {
        switch (newState) {
          case ExampleDeletion$SuccessfulState():
            onSuccessfullyDelete?.call();
            Navigator.pop(context);
          case ExampleDeletion$ErrorState():
            // Texts are literal only to keep the template self-contained: use `Localization.of`.
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Could not delete it')));
          case ExampleDeletion$IdleState() || ExampleDeletion$ProcessingState():
            break;
        }
      },
      builder: (context, state, child) => PopScope(
        canPop: state is! ExampleDeletion$ProcessingState,
        child: AlertDialog(
          title: const Text('Delete'),
          content: const Text('Delete this item?'),
          actions: [
            TextButton(
              onPressed: state is ExampleDeletion$ProcessingState
                  ? null
                  : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: state is ExampleDeletion$ProcessingState
                  ? null
                  : () => controller.delete(exampleId),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### `example_mutation_repositories.dart`

```dart
// file: example_mutation_repositories.dart
import 'example.dart';

/// Writes a record. Create versus update is decided here, not in the controller or the widget.
abstract interface class IExampleCreationRepository {
  /// Creates an example, or updates [existing] when it is given.
  Future<Example> save({required String title, required String content, Example? existing});
}

/// Deletes a record.
abstract interface class IExampleDeletionRepository {
  /// Deletes the example with [id].
  Future<void> delete(int id);
}
```

### `local_pagination_util.dart`

```dart
// file: local_pagination_util.dart
/// Infers whether another page exists from page fullness: a full page means probably yes, a short
/// page means the end. No server `total` is needed.
class LocalPaginationUtil {
  /// Creates the util.
  const LocalPaginationUtil();

  /// The next page to request: [page] + 1 after a full page, [page] after a short one.
  int checkIsListHasMorePageInt({
    required List<Object?> list,
    required int page,
    required int limitInPage,
  }) => list.length >= limitInPage ? page + 1 : page;

  /// Whether another page probably exists.
  bool checkIsListHasMorePageBool({required List<Object?> list, required int limitInPage}) =>
      list.length >= limitInPage;
}
```

### `product.dart`

```dart
// file: product.dart
import 'package:flutter/foundation.dart';

/// A row of the paged list.
@immutable
class Product {
  /// Creates a product.
  const Product({required this.id, required this.name});

  /// Server id.
  final int id;

  /// Display name.
  final String name;
}
```

### `products_controller.dart`

```dart
// file: products_controller.dart
import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'app_exception.dart';
import 'local_pagination_util.dart';
import 'product.dart';
import 'products_repository.dart';

part 'products_controller.freezed.dart';

/// What the list shows, carried by every state: the rows so far, [page] (the NEXT page to
/// request), whether there is more, the server's total, the active search term, and the error of
/// the last failed load, kept so the screen can show it in place of the list.
@freezed
abstract class ProductsData with _$ProductsData {
  const factory ProductsData({
    @Default(<Product>[]) List<Product> products,
    @Default(1) int page,
    @Default(true) bool hasMore,
    @Default(0) int total,
    @Default('') String query,
    Object? error,
  }) = _ProductsData;
}

@freezed
sealed class ProductsState with _$ProductsState {
  const ProductsState._();

  const factory ProductsState.idle({@Default(ProductsData()) ProductsData data}) =
      Products$IdleState;

  const factory ProductsState.processing({required ProductsData data}) = Products$ProcessingState;

  const factory ProductsState.successful({required ProductsData data}) = Products$SuccessfulState;

  const factory ProductsState.error({required ProductsData data, required Object error}) =
      Products$ErrorState;

  /// The rows, in every state.
  List<Product> get products => data.products;

  /// Whether another page can be requested, in every state.
  bool get hasMore => data.hasMore;
}

/// Loads the first page and appends the next ones. The cursor lives in the data every state
/// carries, so a failed page can never leave a hole. The controller keeps no query or filter field.
final class ProductsController extends StateController<ProductsState>
    with SequentialControllerHandler {
  ProductsController({
    required this._productsRepository,
    this._localPaginationUtil = const LocalPaginationUtil(),
    this._limitInPage = 50,
    super.initialState = const ProductsState.idle(),
  });

  final IProductsRepository _productsRepository;
  final LocalPaginationUtil _localPaginationUtil;
  final int _limitInPage;

  /// Page 1; replaces the rows when it lands (they stay on screen meanwhile).
  void load({String query = '', int? categoryId}) => handle(() async {
    setState(ProductsState.processing(data: state.data));
    try {
      final (items, total) = await _productsRepository.products(
        categoryId: categoryId,
        query: query,
        page: 1,
        pageSize: _limitInPage,
      );
      setState(
        ProductsState.successful(
          data: ProductsData(
            products: items,
            page: _nextPage(items, 1),
            hasMore: _hasMore(items),
            total: total,
            query: query,
          ),
        ),
      );
    } on Object catch (error) {
      // Kept in the data: the idle state after it still has the error to show.
      final data = state.data.copyWith(error: error);
      setState(ProductsState.error(data: data, error: error));
      if (error is! ExpectedException) rethrow;
    } finally {
      setState(ProductsState.idle(data: state.data));
    }
  });

  /// Appends the next page. A failure keeps the rows and the cursor, so the page is asked again.
  void paginate({String query = '', int? categoryId}) => handle(() async {
    final current = state.data;
    if (!current.hasMore) return;
    setState(ProductsState.processing(data: current));
    try {
      final (next, total) = await _productsRepository.products(
        categoryId: categoryId,
        query: query,
        page: current.page,
        pageSize: _limitInPage,
      );
      setState(
        ProductsState.successful(
          data: current.copyWith(
            products: _append(current.products, next),
            page: _nextPage(next, current.page),
            hasMore: _hasMore(next),
            total: total,
            query: query,
            error: null,
          ),
        ),
      );
    } on Object catch (error) {
      setState(ProductsState.error(data: current, error: error));
      if (error is! ExpectedException) rethrow;
    } finally {
      setState(ProductsState.idle(data: state.data));
    }
  });

  int _nextPage(List<Product> list, int page) => _localPaginationUtil.checkIsListHasMorePageInt(
    list: list,
    page: page,
    limitInPage: _limitInPage,
  );

  bool _hasMore(List<Product> list) =>
      _localPaginationUtil.checkIsListHasMorePageBool(list: list, limitInPage: _limitInPage);

  /// [next] after [current], by id: a row already shown is replaced where it stands by its newer
  /// copy (offset pages overlap when the list changes between them), new rows go to the end.
  List<Product> _append(List<Product> current, List<Product> next) {
    // A map literal keeps insertion order, and assigning an existing key keeps its position.
    final byId = <int, Product>{for (final product in current) product.id: product};
    for (final product in next) {
      byId[product.id] = product;
    }
    return byId.values.toList(growable: false);
  }
}
```

### `products_data_controller.dart`

```dart
// file: products_data_controller.dart
import 'package:flutter/foundation.dart';

/// The active filter. It lives here, not in the async controller; the config widget reads it and
/// passes it to `load(...)` / `paginate(...)` on every call.
class ProductsDataController with ChangeNotifier {
  int? _filterId;

  /// The selected category, or `null`.
  int? get filterId => _filterId;

  /// Selects a category and notifies listeners when it changed.
  void setFilter(int? value) {
    if (_filterId == value) return;
    _filterId = value;
    notifyListeners();
  }
}
```

### `products_list_widget.dart`

```dart
// file: products_list_widget.dart
import 'package:control/control.dart';
import 'package:flutter/material.dart';

import 'products_controller.dart';

/// Fires [onLoadMore] near the bottom of the list. `controller.isProcessing` guards against a
/// burst of scroll notifications starting several fetches.
class ProductsListWidget extends StatefulWidget {
  const ProductsListWidget({
    super.key,
    required this.controller,
    required this.onLoadMore,
    required this.onRetry,
  });

  final ProductsController controller;

  /// Typically `() => controller.paginate(categoryId: dataController.filterId)`.
  final VoidCallback onLoadMore;

  /// Asks again for what failed: page 1 without rows, the next page with them.
  final VoidCallback onRetry;

  @override
  State<ProductsListWidget> createState() => _ProductsListWidgetState();
}

class _ProductsListWidgetState extends State<ProductsListWidget> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 200) return;
    if (widget.controller.isProcessing) return;
    widget.onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    return StateConsumer<ProductsController, ProductsState>(
      controller: widget.controller,
      // A failed page is a moment: show it, with a retry, from the listener. A failed first load
      // has nothing to show instead, so the builder shows the error in place of the list.
      listener: (context, controller, oldState, newState) {
        if (newState is! Products$ErrorState || newState.products.isEmpty) return;
        // Texts are literal only to keep the template self-contained: use `Localization.of`.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not load the products'),
            action: SnackBarAction(label: 'Try again', onPressed: widget.onRetry),
          ),
        );
      },
      builder: (context, state, child) {
        final products = state.products;
        if (products.isEmpty && state is Products$ProcessingState) {
          return const Center(child: CircularProgressIndicator());
        }
        if (products.isEmpty && state.data.error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Could not load the products'),
                TextButton(onPressed: widget.onRetry, child: const Text('Try again')),
              ],
            ),
          );
        }
        return ListView.builder(
          controller: _scrollController,
          itemCount: products.length + (state.hasMore && products.isNotEmpty ? 1 : 0),
          itemBuilder: (context, index) => index < products.length
              ? ListTile(title: Text(products[index].name))
              : const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
```

### `products_repository.dart`

```dart
// file: products_repository.dart
import 'product.dart';

/// One page and the server's total.
typedef ProductsPage = (List<Product> products, int total);

/// Reads products page by page. App-global scope values (the selected store, the active
/// organisation) are read by the implementation itself, not passed down by widgets.
abstract interface class IProductsRepository {
  /// [page] is 1-based.
  Future<ProductsPage> products({
    String? query,
    int? categoryId,
    required int page,
    required int pageSize,
  });
}
```
