---
name: bloc
description: "Blocs with package:bloc: one file per bloc, one sealed event and one on<> with a switch, the global sequential queue, the four states that all carry data, errors through addError and BlocObserver, config widgets, coordination in widgets, and testing states."
---

# Bloc

This is the state management rule of a project that uses `package:bloc` (`flutter_bloc`). A
project uses one state management package: `control` follows `docs/rules/controllers.md`, a bloc
project follows this file, and has only one of the two in `docs/rules/`. The ideas are the same as
in a `control` project; only the code differs. Where another rule says "controller", read "bloc";
where it says `StateConsumer`, read `BlocBuilder` / `BlocListener`; where it says
`Controller.observer`, read `Bloc.observer`; where it says `handle(...)`, read the handler recipe
below. Where another rule points to a section of `docs/rules/controllers.md`, read the section of
the same name here ("Paginated controllers" is "Paginated blocs"); a bloc project has no
`controllers.md`.

## Rules

- One file per bloc: `lib/<feature>/bloc/<feature>_bloc.dart` holds the event, the state and the
  bloc, with `part '<feature>_bloc.freezed.dart';`. Events and states are freezed `sealed` classes.
  No separate `_event.dart` / `_state.dart` files and no `part of`. See "One file per bloc".
- Event variants are private, named `_<Feature>$<Name>Event`; state variants are public, named
  `<Feature>$<Name>State`. A `///` comment on every event, state and handler says what it does.
- One handler per bloc: `on<FeatureEvent>((event, emit) => switch (event) { ... })`, one case per
  variant, each calling `Future<void> _<feature>$<name>Event(event, emit)`. Never several
  `on<E>`: each one is its own queue, so the event types run over each other on the shared
  state. Handlers return `Future<void>`, never `void ... async`. See "One handler, one queue".
- `Bloc.transformer = sequential()` (`bloc_concurrency`) and `Bloc.observer` are set in the first
  startup step, before any bloc is created: a bloc copies `Bloc.transformer` when it is built. A
  bloc whose every event is a mutation whose repeat is a mistake (create, save, delete, pay) sets
  `transformer: droppable()` on its one `on<>`; no other per-handler transformers.
- States are the same four in every bloc: `idle`, `processing`, `successful`, `error`. Every one
  carries the bloc's data (`FeatureState.idle(data: ...)`), so the screen never loses what it
  shows; `error` also carries the error object. No state per event or per step. See "One recipe
  for states".
- Every handler is one recipe: `try` the happy path (`processing`, the repository, `successful`),
  an optional typed `on X catch` for a reaction of its own, `on Object catch` that calls
  `addError(error, stackTrace)` and emits `error`, and `finally` that emits `idle`. This is the only
  place a bloc catches `Object`. See "Where the error goes".
- `error` is a moment: `idle` follows at once. Widgets show the message from a `BlocListener`
  (SnackBar, banner with a retry); the builder renders the data. An error that must stay on screen
  (a first load that failed) is part of the data, not a state.
- A bloc has nothing of the UI: no `BuildContext`, no `TextEditingController`, `FocusNode`,
  `PageController`, `ScrollController`, `GlobalKey`, widget, `Color`, `ThemeMode` or theme
  colors, no SnackBar or toast, no navigation, no `.tr()` or display text. It imports
  `package:bloc` and `package:meta`, not `flutter_bloc` or `material_ui`. See "No UI in a bloc".
- Events carry data only: no callbacks (`onMessage`, `onDone`, `popUp`), no `Future`s to await,
  no repositories, databases or controllers. The widget learns the result from the next state.
- Synchronous UI state (form fields, the selected tab, a checkbox, a list/grid switch, picked
  images before saving) lives in the widget: a `ValueNotifier` or a `ChangeNotifier` data
  controller. A bloc is for work that is asynchronous and can fail. No `Cubit`.
- States and their data are immutable: every change builds a new list (`List.of`, `[...a, ...b]`)
  and a new model (`copyWith`); never `list.add`, `list.clear`, `item.qty = ...` on something a
  state holds. A bloc has no field that holds data (`_currentState`, `_model`): the data lives in
  `state`. See "Immutable data".
- A guard that makes the event pointless stands first in the handler, before `try`
  (`if (!state.data.hasMore) return;`). A guard on `processing` (`if (state is ...Processing)
  return;`) does nothing under the one sequential queue: the next event starts after the previous
  one ended, so the state is never `processing` there. See "Double taps".
- Blocs never know each other: no bloc in another bloc's constructor or event, no `stream.listen`
  on another bloc inside a bloc. Widgets connect them with a `BlocListener` or a subscription in
  the config widget. See "Blocs talk through widgets".
- A bloc does not `add` events to itself to chain work: an added event goes to the end of the
  queue. Do both steps in one handler. The exception is a stream the bloc subscribed to: see
  "Streams in a bloc".
- A screen's bloc is created in the config widget's `initState`, gets its first event there, is
  given to the subtree with `BlocProvider.value` and closed in `dispose`. A bloc passed in through
  the constructor is used and not closed. See "Creating a bloc for a screen".
- `close()` cancels the bloc's subscriptions and timers and then returns `super.close()`; no I/O,
  no saving, no early `return` before `super.close()`.
- `BlocObserver` logs the bloc, event and state types, never their contents, and hands every error
  to `ErrorUtil.logError`; it shows nothing to the user and calls no crash reporter itself. See
  "The observer".
- Test a bloc through its states with `bloc.stream`, `emitsInOrder` and `isA<...>().having(...)`;
  stub its repository with `mocktail`; no `bloc_test`. See "Testing a bloc".

## What a bloc is

A bloc (Business Logic Component) separates the widgets from the data with publish/subscribe:
widgets add events (in) and listen to states (out); the bloc does not know who listens. It is not
one bloc per screen, not a view model and not a store for the whole app: one bloc is one domain
concern of a feature (a list, a creation, a deletion). Its states hold the feature's own models,
never DTOs or database rows. Business rules live in repositories; the bloc orders the calls and
turns them into states.

## One file per bloc

```dart
import 'package:bloc/bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'products_bloc.freezed.dart';

/// Events of [ProductsBloc].
@freezed
sealed class ProductsEvent with _$ProductsEvent {
  /// Loads the first page again.
  const factory ProductsEvent.load() = _Products$LoadEvent;

  /// Loads the next page.
  const factory ProductsEvent.paginate() = _Products$PaginateEvent;
}

/// States of [ProductsBloc]: every one carries [ProductsData].
@freezed
sealed class ProductsState with _$ProductsState {
  const ProductsState._();

  /// Nothing is running.
  const factory ProductsState.idle({required ProductsData data}) = Products$IdleState;

  /// An event is running; [data] is what the screen still shows.
  const factory ProductsState.processing({required ProductsData data}) = Products$ProcessingState;

  /// The event finished; [data] is its result.
  const factory ProductsState.successful({required ProductsData data}) = Products$SuccessfulState;

  /// The event failed; [data] is unchanged.
  const factory ProductsState.error({required ProductsData data, required Object error}) =
      Products$ErrorState;

  /// The state a new bloc starts from.
  static const ProductsState initial = ProductsState.idle(data: ProductsData.empty);

  /// A flag the UI needs is a getter, not a state of its own.
  bool get isProcessing => this is Products$ProcessingState;
}

/// The products list with its pages.
final class ProductsBloc extends Bloc<ProductsEvent, ProductsState> {
  /// Creates the bloc; [initialState] is for tests.
  ProductsBloc({required this._repository, ProductsState? initialState})
    : super(initialState ?? ProductsState.initial) {
    on<ProductsEvent>(
      (event, emit) => switch (event) {
        final _Products$LoadEvent event => _products$LoadEvent(event, emit),
        final _Products$PaginateEvent event => _products$PaginateEvent(event, emit),
      },
    );
  }

  final IProductsRepository _repository;

  /// Reads the first page; the old rows stay on screen until the new ones come.
  Future<void> _products$LoadEvent(_Products$LoadEvent event, Emitter<ProductsState> emit) async {
    try {
      emit(ProductsState.processing(data: state.data));
      final page = await _repository.page(1);
      emit(ProductsState.successful(data: ProductsData.firstPage(page)));
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(ProductsState.error(data: state.data, error: error));
    } finally {
      emit(ProductsState.idle(data: state.data));
    }
  }

  /// Appends the next page; nothing to do when there is none.
  Future<void> _products$PaginateEvent(
    _Products$PaginateEvent event,
    Emitter<ProductsState> emit,
  ) async {
    if (!state.data.hasMore) return;
    try {
      emit(ProductsState.processing(data: state.data));
      final page = await _repository.page(state.data.nextPage);
      emit(ProductsState.successful(data: state.data.withPage(page)));
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(ProductsState.error(data: state.data, error: error));
    } finally {
      emit(ProductsState.idle(data: state.data));
    }
  }
}
```

- A field declared in every variant (`data`) is on the union itself: `state.data` works in any
  state.
- Several values that travel together (`rows`, `nextPage`, `hasMore`) are one immutable data class
  (`ProductsData`) with `copyWith` or named constructors, not separate fields of every variant.
- `build.yaml` generates freezed for `lib/**/bloc/*.dart`.
- Read a state with a `switch` over its cases or a getter on the state, not with the generated
  `when` / `map` / `maybeMap`.

## One handler, one queue

Calls that overlap race on the bloc's state. A bloc prevents that with one queue (checked:
`bloc` 9.2.1):

- Each `on<E>` subscribes to the event stream with its own transformer. Two `on<E>` keep their own
  order but run at the same time over the same state, and `sequential()` on each of them does not
  change that. One `on<SealedEvent>` with a `switch` puts every event in one queue.
- A bloc copies `Bloc.transformer` when it is constructed (`final _eventTransformer =
  Bloc.transformer`): set it in the first startup step, before the first bloc exists.
- With `sequential()` the next event starts only when the previous handler's `Future` completed.
  A handler declared `void ... async` returns that `Future` under the type `void`; it works by
  accident and hides it from the analyzer. Declare `Future<void>` and await every call inside.
- `droppable()` drops an event that arrives while one runs: right for a bloc of mutations (save,
  delete, sign in, pay), where a second tap is a mistake. Put it on the one `on<>` of that bloc.
  `restartable()` and `concurrent()` are not used: a search drops stale answers with a debounce in
  the widget and a query check in the handler.
- An emit after the handler completed fails an assertion in debug ("emit was called after an
  event handler completed normally"): the sign of a missing `await`.
- After `close()`, a pending handler's emits are dropped silently, and `add` throws
  (`Cannot add new events after calling close`). Widgets stop adding before they close the bloc;
  a callback that can fire late checks `bloc.isClosed`.
- A bloc drops a state that is `==` to the current one (no `onChange`, no `onTransition`, no
  rebuild). Freezed states are equal by value, so emitting the same `idle(data: x)` twice is one
  state; mutating `x` in place and emitting it again is nothing at all.

## One recipe for states

The four states are the same in every bloc, so every widget and every test reads them the same way.
The data travels through all four; only the variant says what is happening now. Adding an event
adds no state. A state per step (`initial`, `sending`, `verification`, `transfer`,
`transferLoading`, ...) multiplies with every step and makes every reader check which ones still
hold data: a wizard's step is a field of the data (`data.step`), not a state.

- `successful` is followed by `idle` in the same handler (`finally`). A listener that reacts to a
  finished action (close the dialog, refresh another list) checks `state is ...SuccessfulState`.
- An event that does no I/O and cannot fail (applying a value the widget already validated)
  emits `idle(data: newData)` and nothing else.
- An event without data (a deletion bloc) uses the four states without the `data` field.

## Where the error goes

```dart
Future<void> _draft$SaveEvent(_Draft$SaveEvent event, Emitter<DraftState> emit) async {
  try {
    emit(DraftState.processing(data: state.data));
    final saved = await _repository.save(event.draft, version: state.data.version);
    emit(DraftState.successful(data: state.data.withSaved(saved)));
  } on VersionConflictException {
    // Someone saved first: take the newest version instead of showing a failure.
    emit(DraftState.successful(data: state.data.withSaved(await _repository.latest(event.draft.id))));
  } on Object catch (error, stackTrace) {
    addError(error, stackTrace);
    emit(DraftState.error(data: state.data, error: error));
  } finally {
    emit(DraftState.idle(data: state.data));
  }
}
```

- `addError` calls `onError`, which calls `Bloc.observer.onError`: every error reaches the
  observer once, and the observer gives it to `ErrorUtil`, which keeps expected failures out of
  the crash reporter. See "Expected and unexpected errors".
- An error that leaves a handler is reported by the bloc itself (`onError`) and then rethrown into
  the zone, where it is reported a second time: never let one out. `on Object { emit(...);
  rethrow; }` and `Error.throwWithStackTrace` in a handler do exactly that.
- `addError` without an `error` state leaves the screen in `processing` forever (a spinner that
  never stops, a theme that never loads). The recipe always emits `error` and `idle`.
- The `error` state holds the error object, never a display string; the widget turns it into text
  with `errorText(lcl, error)` (see "Error messages" in `docs/rules/localization.md`).
- A typed `on X catch` is for a reaction of its own only (a conflict the bloc resolves, a value to
  fall back to); that error is handled there and is not reported. `rethrow` inside a typed `on`
  hands the cases of that type that need no reaction to the `on Object` below.
- An expired session (401) is not caught in every handler to reset the screen: it is the
  authentication middleware's (it refreshes the token or signs the user out, see "HTTP
  middleware" in `docs/rules/dependencies.md`), and the bloc shows it as any other `error`.
- A side read the screen can do without (a counter, a hint) may be caught with `on Exception
  catch` and reported with `ErrorUtil.logError(error, stackTrace, hint: '...')` right there, with
  a comment saying why the event goes on.
- Await every `Future` inside a handler; a `Future` started and not awaited escapes the `try`.

### Expected and unexpected errors

Not every failure is a bug. A wrong password, a taken email or a value the server rejected is the
feature's answer: the user reads it and acts. A failed parse, a `StateError` or a server 500 is
not: someone has to look at it. The crash reporter is for the second kind only.

- The data layer marks the expected kind where it reads the server's answer: it throws a subtype
  of `ExpectedException` (`RejectedException(code: 'wrong_password')`), see "Errors" in
  `docs/rules/repositories.md`.
- The bloc does not tell them apart: every error gets `addError` and the `error` state, and the
  screen shows both through `errorText`.
- What counts as expected is decided in one place, `isExpectedFailure` of the app
  (`lib/_core/telemetry/expected_failure.dart`): the network and 5xx, a timeout, a dropped
  connection, 401/403, and every `ExpectedException`. `ErrorUtil` writes both kinds to the log
  and queues only the unexpected one for the crash reporter. A new kind of expected failure is
  added there, not in a `catch`.

### Reporting an error

`ErrorUtil` is the one place where code reports an error: `ErrorUtil.logError(error, stackTrace,
hint: ...)` for an exception, `ErrorUtil.logMessage(...)` for a failure that did not throw. A
project with another reporter keeps it and follows the same split.

- It writes the record to the log and, if the error is unexpected, queues it for the crash
  reporter with the last log lines. It never throws, so a `catch` may call it without a `try`.
- `print`, `debugPrint` and `developer.log` are not used for errors; progress messages go through
  `l` (`l.i`, `l.w`).
- The places that call it: the bloc observer, the zone and platform handlers, the startup, and a
  `catch` that swallows an error on purpose (a side read). A bloc handler reports through
  `addError`; a widget never reports.
- Secrets are removed before the queue; still, put no token, password or key in a message.

### Cached data first, then fresh

When a screen shows the cached data and then the fresh, the repository has two methods
(`cached()`, `fetch()`) and the handler calls both, in order:

```dart
Future<void> _profile$LoadEvent(_Profile$LoadEvent event, Emitter<ProfileState> emit) async {
  try {
    emit(ProfileState.processing(data: state.data));
    final cached = await _repository.cached();
    if (cached != null) emit(ProfileState.processing(data: state.data.copyWith(user: cached)));
    emit(ProfileState.successful(data: state.data.copyWith(user: await _repository.fetch())));
  } on Object catch (error, stackTrace) {
    addError(error, stackTrace);
    emit(ProfileState.error(data: state.data, error: error));
  } finally {
    emit(ProfileState.idle(data: state.data));
  }
}
```

The cached rows stay on screen while the fresh ones load; a failed fetch keeps them.

## No UI in a bloc

The bloc layer and everything below it (repositories, data providers, models) imports no Flutter UI:

- Text fields keep their `TextEditingController` in the widget; the widget sends the values with the
  event that needs them (`DraftEvent.save(name: _name.text, price: _price.text)`), or validates
  them itself first.
- Focus, scrolling, pages, animations and dialogs are the widget's. The bloc never calls
  `FocusManager`, `animateToPage`, a phone dialer or a toast.
- Navigation and messages come from a `BlocListener` that reads the state change.
- Theme colors and `ThemeMode` are not a bloc's state: the widget takes colors from
  `context.colors` (see `docs/rules/widgets.md`). A settings bloc keeps the user's choice as data
  (`ThemeChoice.dark`), and the app widget maps it to `ThemeMode`.
- Display text is the widget's: no `.tr()`, no Russian or English message in a state.

## Immutable data

- Build the next list from the current one: `final rows = [...state.data.rows, ...page.rows];`,
  `List.of(state.data.rows)..removeAt(index)`. A shallow `copyWith()` followed by
  `copy.items.add(x)` changes the list the previous state still holds.
- A model in a state is never mutated (`item.qty = ...`, `model.addToParents(...)`); build a new
  one with `copyWith`.
- A model's `copyWith` that must clear a nullable field takes a `ValueGetter`:
  `copyWith(city: () => null)`.
- A bloc keeps no data in its own fields; its private fields are what its constructor received and
  its subscriptions and timers.

## Double taps

The queue makes a second event wait; it does not drop it:

- A button whose action is running is disabled by its widget, from the state
  (`onPressed: state.isProcessing ? null : _save`), and a dialog with an async action is wrapped in
  `PopScope(canPop: !state.isProcessing)`.
- A bloc of mutations sets `transformer: droppable()` on its one `on<>`.
- A guard on the data (`if (state.data.saved) return;`) is the bloc's own check that the event is
  still needed when its turn comes.

## Blocs talk through widgets

Blocs of one feature, and of different features, never import each other. The widget that owns
them connects them:

```dart
BlocListener<ProductCreationBloc, ProductCreationState>(
  listenWhen: (previous, current) => current is ProductCreation$SuccessfulState,
  listener: (context, state) => context.read<ProductsBloc>().add(const ProductsEvent.load()),
  child: const ProductCreationForm(),
)
```

- React to a transition (`listenWhen` with the previous and current state), not to a state that may
  be emitted again.
- A config widget that needs another bloc's result subscribes to its `stream` in `initState`,
  adds an event to its own bloc, and cancels the subscription in `dispose`.
- Data is not copied from one bloc into another ("load from another bloc's data"): the repository
  that owns it caches it, and both blocs read it from there.
- App-wide blocs (authentication, settings) are read by widgets; a feature bloc that needs the
  user gets it as an event argument from the widget.

## Streams in a bloc

A bloc that follows a stream (location, a socket, a database watch) subscribes in a handler, turns
each item into a private event, and cancels in `close()`:

```dart
StreamSubscription<Position>? _positions;

Future<void> _tracker$StartEvent(_Tracker$StartEvent event, Emitter<TrackerState> emit) async {
  await _positions?.cancel();
  _positions = _repository.positions().listen(
    (position) => add(TrackerEvent.position(position)),
    onError: addError,
  );
}

@override
Future<void> close() async {
  await _positions?.cancel();
  return super.close();
}
```

- The private item event goes through the same queue as the others, so an item never interleaves
  with a running event.
- `emit.forEach` keeps its handler running for as long as the stream lives and, under
  `sequential()`, blocks every other event: use it only in a bloc that does nothing else.

## Creating a bloc for a screen

A config widget owns the screen's blocs:

```dart
class ProductsConfigWidget extends StatefulWidget {
  const ProductsConfigWidget({super.key, this.bloc});

  /// A bloc made elsewhere (a test, a parent that shares it); this widget does not close it.
  final ProductsBloc? bloc;

  @override
  State<ProductsConfigWidget> createState() => _ProductsConfigWidgetState();
}

class _ProductsConfigWidgetState extends State<ProductsConfigWidget> {
  late final ProductsBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc =
        widget.bloc ??
        (ProductsBloc(repository: DependenciesScope.of(context).productsRepository)
          ..add(const ProductsEvent.load()));
  }

  @override
  void dispose() {
    if (widget.bloc == null) _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocProvider.value(value: _bloc, child: const ProductsScreen());
}
```

- The bloc is built synchronously and starts loading at once; the screen never waits for it.
- Every bloc the widget created is closed in `dispose`, right away (no `Future.delayed`).
- `BlocProvider(create: ...)` is not used for a screen's bloc: the config widget owns its life.
- A modal route's bloc is built where the route opens and closed when it closes:
  `showSearch(...).whenComplete(bloc.close).ignore();`.
- App-wide blocs are created in an initialization step, kept in `Dependencies`, given to the tree
  by `DependenciesScope` (or one `MultiBlocProvider` of `.value` above the app), and closed when
  the dependencies are disposed.

## Consuming a bloc in widgets

- `BlocBuilder` renders with a `switch` over the state, or reads `state.data` directly when every
  state shows the same data.
- `BlocListener` is for effects: a SnackBar for `error`, closing a dialog after `successful`,
  navigation.
- `context.select((ProductsBloc bloc) => bloc.state.data.count)` or `BlocSelector` rebuilds only
  on the one value; `context.watch<XBloc>()` in `build` rebuilds the whole widget on every state.
- Events are added from callbacks: `context.read<ProductsBloc>().add(...)`, never in `build`.

## The observer

```dart
import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:l/l.dart';
import 'package:my_app/_core/telemetry/error_util.dart';

/// Observes every bloc: their events, transitions and errors.
final class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onCreate(BlocBase<Object?> bloc) {
    super.onCreate(bloc);
    l.v6('Bloc | ${bloc.runtimeType}.new');
  }

  @override
  void onEvent(Bloc<Object?, Object?> bloc, Object? event) {
    super.onEvent(bloc, event);
    l.d('Bloc | ${bloc.runtimeType} | ${event.runtimeType}');
  }

  @override
  void onTransition(Bloc<Object?, Object?> bloc, Transition<Object?, Object?> transition) {
    super.onTransition(bloc, transition);
    // Types only: a state may hold tokens and people's data, and the log goes into crash reports.
    l.v(
      '${bloc.runtimeType}: ${transition.currentState.runtimeType} -> '
      '${transition.nextState.runtimeType}',
    );
  }

  @override
  void onError(BlocBase<Object?> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    unawaited(ErrorUtil.logError(error, stackTrace, hint: '${bloc.runtimeType} failed'));
  }

  @override
  void onClose(BlocBase<Object?> bloc) {
    super.onClose(bloc);
    l.v5('Bloc | ${bloc.runtimeType}.close');
  }
}
```

Set it in the first startup step, with the queue:

```dart
Bloc.transformer = sequential();
Bloc.observer = const AppBlocObserver();
```

## Testing a bloc

```dart
class MockProductsRepository extends Mock implements IProductsRepository {}

void main() {
  late MockProductsRepository repository;

  setUp(() => repository = MockProductsRepository());

  test('load goes processing, successful, idle with the first page', () async {
    when(() => repository.page(1)).thenAnswer((_) async => page1);
    final bloc = ProductsBloc(repository: repository);
    addTearDown(bloc.close);

    final states = expectLater(
      bloc.stream,
      emitsInOrder(<Matcher>[
        isA<Products$ProcessingState>(),
        isA<Products$SuccessfulState>().having((s) => s.data.rows, 'rows', page1.rows),
        isA<Products$IdleState>(),
      ]),
    );
    bloc.add(const ProductsEvent.load());
    await states;
  });

  test('a failed load keeps the rows and goes back to idle', () async {
    when(() => repository.page(1)).thenThrow(StateError('offline'));
    final bloc = ProductsBloc(
      repository: repository,
      initialState: ProductsState.idle(data: someRows),
    );
    addTearDown(bloc.close);

    final states = expectLater(
      bloc.stream,
      emitsInOrder(<Matcher>[
        isA<Products$ProcessingState>(),
        isA<Products$ErrorState>()
            .having((s) => s.error, 'error', isStateError)
            .having((s) => s.data, 'data', someRows),
        isA<Products$IdleState>(),
      ]),
    );
    bloc.add(const ProductsEvent.load());
    await states;
  });
}
```

- `bloc.stream` is a broadcast stream that does not buffer: start the expectation, then add the
  event, then await the expectation.
- Stub the repository (the bloc's interface), never the bloc.
- `initialState` puts the bloc where the test starts (a loaded list, a page in the middle).
- To check reporting, set `Bloc.observer` to a fake that records `onError` calls and put the old one
  back with `addTearDown`.
- A widget test gives the screen a bloc through the config widget's `bloc` parameter.

## Paginated blocs

The data class holds the rows, the next page and whether there is more; the bloc has `load`
(first page again, rows kept on screen until the new ones come) and `paginate` (the next page,
skipped when `!hasMore`). A failed page keeps the rows: the `error` state carries the old data, and
the list shows a retry at its end. The widget triggers `paginate` near the end of the list, not
while `state.isProcessing`. A list without pages keeps the same shape with `hasMore: false`.

## Mistakes to avoid

Seen in real bloc projects; each breaks one rule above:

- A mutable model kept in a bloc field (`late final _currentState = state.model`), changed in place
  and emitted again: the bloc drops the "new" state because it is the same object.
- Ninety `on<E>` handlers with `droppable()` on some and `restartable()` on others: event types
  overlap on the shared state.
- The whole form in the state: a dozen `TextEditingController`s, a `FocusNode`, `PageController`s
  and a list of page widgets, with Hive writes in the model's methods.
- `UnAuthenticatedException` caught in every handler to reset the screen to its first state, which
  throws away what the screen showed.
- A failed page emitting an `error` state without data: the whole list disappears.
- `if (state is ...Processing) return;` at the top of a handler: dead code under one sequential
  queue; a double tap still runs twice.
- `close()` with a `return` before `super.close()`, or a bloc created in `initState` and never
  closed.
- A config widget that closes a bloc passed in by its parent, or closes its own one after
  `Future.delayed`.
- Callbacks passed down into the repository (`saveSearch(filter, event.onMessage)`).
