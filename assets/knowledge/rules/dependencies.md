---
name: dependencies
description: "Pure DI: the graph is built by hand at startup, dependencies come through constructors and context; no service locator."
---

# Dependencies

## Rules

- App-wide services live in `Dependencies` and are read with `DependenciesScope.of(context)`.
  Add a new service as a step of the app's initialization.
- A feature config widget creates its controllers in `initState`, builds repositories from
  `DependenciesScope`, disposes controllers in `dispose` and exposes itself through
  `XConfigInhWidget.of(context)` (`updateShouldNotify` returns `false`).
- Widgets get controllers from that scope, never from a repository.
- Code against `IFooRepository` interfaces; give dependencies to constructors, never create them
  inside a controller.
- Pure DI, no service locator: no `GetIt.instance`, no global or static holder of services, no DI
  container (`injectable`). Dependencies come through the constructor, and widgets read them only
  from `context`. See "Pure DI, not a service locator".
- One HTTP client, configured once at startup (base URL, headers, interceptors), shared by every
  repository and data provider; a second client only for a real difference. It returns decoded
  JSON and throws the app's own exceptions, never the transport's. See "HTTP clients".
- At startup, the stored session (a local read) is awaited before the first frame; checking it
  with the server is started and not awaited. See "Startup and creating dependencies".
- Constructors are synchronous, always: no "async factory" for a controller or repository. Async work
  (loading, reading the disk) is a method the controller runs after it is built. See "Startup and
  creating dependencies".

## Dependency injection

### Pure DI, not a service locator

Three things get called "DI" and are not the same:

- **Dependency injection (DI)**: an object gets its dependencies from outside, already built,
  instead of creating or fetching them. The usual form is constructor injection:
  `ExampleController({required IExampleRepository repository})`.
- **Service locator (SL)**: a box you register objects in and take them out of later, from
  anywhere (`get_it`). Reading dependencies from a global service locator instead of the
  constructor hides them: a class's constructor no longer says what it needs, any code can reach
  any service, and a test has to remember to register everything first.
- **DI container**: registers classes and builds them itself, passing each one the dependencies its
  constructor asks for, in the right order (`injectable` on top of `get_it`). It does DI for you,
  through a service locator, with code generation.

This project uses **Pure DI** (Poor Man's DI): the whole graph is built by hand, in order, at
startup, in the steps of `initialize_dependencies.dart`, and handed down through constructors and
`context`. Nothing is magic and every dependency is visible in a constructor.

- A widget reads a dependency only through `context`: `DependenciesScope.of(context)` for app-wide
  services, `XConfigInhWidget.of(context)` for a feature's controllers. Never from a global variable
  or a static field, even when one would be shorter.
- Reading an `InheritedWidget` is cheap: `dependOnInheritedWidgetOfExactType` and
  `getInheritedWidgetOfExactType` are a hash-map lookup (O(1)) kept by every element.
  `findAncestorWidgetOfExactType` is the one that walks up the tree (O(depth)); never use it to
  find a scope.
- A class that is not a widget gets everything through its constructor; it never reaches for
  `context` or a locator.
- Expose things with your own scopes, not the `provider` package. A scope is a `StatefulWidget`
  that owns what it exposes, a private `InheritedWidget` its `State` builds around the child, and a
  static `of(context)` on the public widget. `of` reads with `getInheritedWidgetOfExactType` (no
  rebuild); offer `of(context, listen: true)` with `dependOnInheritedWidgetOfExactType` only for a
  value whose change must rebuild the reader, and then `updateShouldNotify` returns `true` when it
  changed. The config widgets below are such scopes.
- A scope whose readers must rebuild when a `Listenable` notifies is an `InheritedNotifier`: it is
  what `provider` does for a `ChangeNotifier`, without the package. Using a `ChangeNotifier` does
  not mean using `provider`.

### Global: `Dependencies` and `DependenciesScope`

App-wide services are created once at startup, held by a `Dependencies` object and exposed to the
tree by `DependenciesScope` (template `dependencies.dart`).

```dart
class Dependencies {
  late final AppMetadata metadata;
  late final SharedPreferences sharedPreferences;
  late final AppDatabase database;
  late final ApiClient apiClient;
  late final InternetConnectionController internetConnectionController;
  // ... other dependencies

  Widget inject({required Widget child, Key? key}) =>
      DependenciesScope(dependencies: this, key: key, child: child);
}

class DependenciesScope extends InheritedWidget {
  const DependenciesScope({required this.dependencies, required super.child, super.key});

  final Dependencies dependencies;

  static Dependencies of(BuildContext context) =>
      maybeOf(context) ?? _notFoundInheritedWidgetOfExactType();

  @override
  bool updateShouldNotify(covariant DependenciesScope oldWidget) => false;
}
```

Provide it once at the top, and read it anywhere:

```dart
dependencies.inject(child: MaterialApp(...))   // main app setup
final deps = DependenciesScope.of(context);    // in widgets
```

A new app-wide service is a new late field plus an initialization step that creates it before the
app runs. If the project has an `initialize_dependencies` file, add the step there.

### Startup and creating dependencies

- **Nothing created at startup throws or waits on the outside world.** Opening the database,
  reading preferences, building the API client: local, fast, reliable. Restoring the session is
  two steps. Reading the stored tokens from the Keychain or Keystore is local, and the first screen
  depends on it (sign-in or home): await it, with a timeout inside, and treat a failure as signed
  out (`AuthSession.restore` in `docs/rules/security.md`). Checking the session with the server
  (the user's profile, whether the account still exists) calls the network: start it, never await
  it.
- **No lazy global dependencies "to save memory".** A controller or repository object costs nearly
  nothing; creating it eagerly is simpler and fails early instead of on some later screen.
- **Riverpod and `get_it` are global variables too.** A provider declared at the top level is a
  global variable, wrapped in more machinery, that builds the repository and keeps it in memory;
  `ProviderScope` does not make it anything else. Dart's top-level and static variables are already
  lazy (initialized on first read), so the wrapper buys nothing. A repository, client or data
  provider is a small class with a few methods: create it at startup and pass it down. What lives
  with a screen (text controllers, a state machine) is created in that screen's `initState`.
- **There are no async constructors.** Dart constructors and factory constructors are synchronous,
  and so is creating a controller or repository. An `AsyncFactory` that `await`s something before it
  returns a controller is the wrong shape: build the controller at once, and let it load what it
  needs in a method (`fetchAll()`), going `processing` → `idle` with the data. A static `Future`
  method that builds an object is possible, but controllers and repositories never need one.
- **A dependency that a screen needs is passed in, already built**, through the constructor or
  `context`; never awaited while the user waits for the screen to open.
- **Pass data through methods, not the constructor.** A controller that needs the current user takes
  it as an argument of the call (`load(user: user)`), rather than depending on a user repository or a
  user object in its constructor. The fewer constructor dependencies, the simpler the class.
- **If a dependency really is asynchronous** (rare: almost always the code above is the answer), wrap
  the subtree in a small widget that waits for it and shows a placeholder meanwhile:

```dart
/// Builds [builder] once [dependency] is ready, [loading] until then.
class AsyncDependency<T> extends StatelessWidget {
  const AsyncDependency({
    required this.dependency,
    required this.builder,
    this.loading = const Center(child: CircularProgressIndicator()),
    super.key,
  });

  final Future<T> dependency;
  final Widget Function(BuildContext context, T dependency) builder;
  final Widget loading;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: dependency,
    builder: (context, snapshot) =>
        snapshot.hasData ? builder(context, snapshot.requireData) : loading,
  );
}
```

  Create the `Future` once (in a `State` field, not in `build`), or `FutureBuilder` restarts it on
  every rebuild. A future that can fail needs a `snapshot.hasError` branch, or the placeholder
  stays forever.

### Initialization steps

Startup is a list of named steps run in order, each filling in part of `Dependencies`:

```dart
final Map<String, InitializationStep> initializationSteps = <String, InitializationStep>{
  'Shared preferences': (d) async => d.sharedPreferences = await SharedPreferences.getInstance(),
  'Database': (d) => d.database = Config.inMemoryDatabase ? AppDatabase.memory() : AppDatabase(),
  'API client': (d) => d.apiClient = ApiClient(baseUrl: Config.apiUrl, middlewares: [...]),
  'Authentication': (d) => d.authenticationController = AuthenticationController(
    repository: AuthenticationRepositoryImpl(database: d.database, apiClient: d.apiClient),
  ),
  // The Keychain or Keystore, with a timeout: awaited, the first screen depends on it.
  'Restore the session': (d) => d.authenticationController.restore(),
  // The network: started, never awaited, so a slow server never holds the splash.
  'Check the session': (d) => d.authenticationController.refreshUser().ignore(),
  'Settings': (d) async {
    d.settingsController = SettingsController(repository: SettingsRepositoryImpl(database: d.database));
    await d.settingsController.fetch(); // local and fast: the first screen needs it
  },
};

Future<void> main() async {
  try {
    final dependencies = await initializeApp(steps: initializationSteps);
    runApp(dependencies.inject(child: const App()));
  } on Object catch (error) {
    runApp(InitializationFailedApp(error: error)); // a screen with the error and a retry
  }
}
```

- The steps are a map from a name to a function: the order is visible in one place, the name goes
  to the log and the progress, and a failed step says which one it was (`initialization.dart`).
- A new app-wide service is a new step, in the place where what it needs already exists.
- The first frame is deferred (`deferFirstFrame`) until the steps are done, so the native splash
  stays on screen instead of an empty frame; `allowFirstFrame` after the first `runApp` frame.
- The error handlers and `Controller.observer` are set before the first step, so a failing step
  is already reported.
- Work that may wait on the network (checking the session with the server) is started and not
  awaited (`.ignore()`), so a slow server never holds the splash; what the first screen needs from
  local storage is awaited. Reading the stored session is such a local step: not awaiting it draws
  the first frame as signed out, and a signed-in user sees the sign-in page flash before home.
- The steps may fill a mutable holder that only initialization sees (`$MutableDependencies` with
  plain fields) and end with `freeze()`, which returns the app's immutable `Dependencies` (an
  interface with final fields): nothing after startup can reassign a service, and there are no
  `late` fields to read too early.
- Callbacks connect services created in different steps without making them depend on each other:
  the API client reads the token and signs out on a 401 through closures over `Dependencies`, so
  it never imports the authentication controller. See "Callbacks instead of references".

### Uncaught errors

Set the app's error handlers first thing in `main`, before anything else runs, and send what they
catch to the log and the crash reporter:

- `FlutterError.onError`: errors the framework catches itself (in `build`, layout, paint, and
  gesture callbacks).
- `PlatformDispatcher.instance.onError`: errors nothing caught, such as a failed `Future` nobody
  awaited. Return `true` once it is reported. (`runZonedGuarded` around `runApp` does the same
  job; `WidgetsFlutterBinding.ensureInitialized()` must then run inside that zone.)
- Controllers report their own errors through their observer (`Controller.observer`, `BlocObserver`
  in `bloc`): an awaited error inside `handle` reaches neither handler above. See "Where the
  rethrown error goes" in `docs/rules/controllers.md`.

### Callbacks instead of references

A constructor can take functions as well as interfaces. A class then reaches the outside world
(asks for a value, reports an event) without holding a reference to what answers:

```dart
final users = StreamController<User>.broadcast();
final client = ApiClient(
  baseUrl: Config.apiUrl,
  getToken: session.accessToken, // from memory, see "Tokens" in docs/rules/security.md
  onUnauthorized: () => authenticationController.signOut().ignore(),
  onUser: users.add,
);
```

- The client does not know the authentication controller, the preferences or the stream; whoever
  creates it decides what the callbacks do. That breaks the cycle a client and an authentication
  controller otherwise make (each needs the other).
- It suits a package in plain Dart that a Flutter app will use: the package declares
  `String? Function() getToken` and needs nothing from Flutter or the app.
- With several related callbacks, declare a small interface instead (`ITokenStorage` with `read` and
  `clear`), which the app implements.

### Context shortcuts

Widgets read the same things over and over (dependencies, localization, navigation). Gather the
shortcuts behind one extension getter, `context.ext`, which returns an extension type over the
context: `context.ext.dependencies`, `context.ext.push(page)`. The helpers stay in one place, they
do not crowd the autocomplete of `BuildContext` itself, and the wrapper costs nothing at run time
(example `context_extension.dart`).

- Group further by area when it grows: `context.ext.lcl.errors` for one localization,
  `context.ext.settings.darkMode()` for settings read through an `InheritedModel` aspect.
- A shortcut that reads something that can change takes `{bool listen = true}` and picks
  `dependOn...` or `get...` accordingly, like the scopes it wraps.
- Shortcuts that act rather than read (`context.ext.hapticLight()`, which checks the haptics
  setting first; `push`) read what they need with `listen: false`: they run in callbacks, where
  subscribing is wrong.
- Shortcuts are for widgets only: nothing below the widgets takes a `BuildContext`.

### HTTP clients

Create the HTTP client once, as an app-wide dependency, with its base URL, default headers,
interceptors and timeouts, and pass that instance to every repository or data provider through
its constructor. Reusing it keeps one configuration and reuses open connections.

```dart
// initialize_dependencies.dart
dependencies.apiClient = ApiClient(
  baseUrl: config.apiUrl,
  interceptors: <ApiInterceptor>[AuthInterceptor(tokens: dependencies.tokens)],
);

// Every repository gets the same instance.
ProductsRepositoryImpl(apiClient: dependencies.apiClient);
OrdersRepositoryImpl(apiClient: dependencies.apiClient);
```

The client class is the one place that knows the transport. Its methods (`get`, `post`, `put`,
`patch`, `delete` with a path, a body, headers and query parameters) return the decoded JSON
(`Map<String, Object?>`), and it makes the first translation of failures into the app's own
exceptions, the ones `errorText` knows (see "Error messages" in `docs/rules/localization.md`):

- no connection or a timeout: `NetworkException`, `TimeoutException`;
- 401, 403, 404, 5xx: `UnauthorizedException`, `ForbiddenException`, `NotFoundException`,
  `ServerException`;
- an error body from the backend: `RejectedException` with its code and message;
- a body that is not JSON: `FormatException`.

Each keeps the original stack trace (`Error.throwWithStackTrace`). Data providers then only turn
the map into models and the backend's codes into their own meaning (see "Errors" in
`docs/rules/repositories.md`); they never see `DioException`, `ClientException` or a status code.
Swapping Dio for `package:http` or `cupertino_http` changes one class, and a provider's test
fakes this client (return a map, or throw) instead of building responses and bytes.

A second client is for a real difference, not for every feature:

- a different cache, cookie jar or set of interceptors (a public CDN next to the signed-in API);
- keep-alive on for the API and off elsewhere;
- large downloads through the platform's own client (a background download), so they do not hold
  up API calls.

Head-of-line blocking is the reason to keep long transfers apart: on one connection, a slow
response holds up the requests behind it. HTTP/1.1 has it per connection, HTTP/2 multiplexes
requests but still blocks at the TCP level, and HTTP/3 (QUIC) removes it; most backends still
serve HTTP/1.1. `dart:io`'s `HttpClient` opens a connection per concurrent request
(`maxConnectionsPerHost` is unlimited by default) and does not pipeline, so one client rarely
blocks itself. Checked against a local server where `/a` takes a second: three requests at once
used three connections and `/b` and `/c` answered in about 30 ms; with `maxConnectionsPerHost =
1` they waited for `/a`. Keep-alive only reuses a connection that is free; browsers open several
per host. A client limited to few connections, or a proxy that serialises them, does block.

### HTTP middleware

Cross-cutting work around every request (the token, retries, logging, the connection state) is
middleware of the one client, each kind in its own: a function that takes the next handler and
returns a handler that wraps it (`ApiClientHandler call(ApiClientHandler next) => (request, ...)
async { ... }`). The order of the list is the order of the wrapping: authentication inside retry
retries with a fresh token; a connection-state middleware outside retry reports "offline" only
after the last attempt.

- **Authentication**: adds the token from memory (see "Tokens" in `docs/rules/security.md`). On a
  401 it refreshes once and retries the request once, with a copy (a request whose body is a
  stream cannot be sent twice: fail instead). A 401 on a request sent without a token (sign-in,
  a one-time code) is a wrong code, not an expired session: no refresh. A 403 is a missing
  permission: never sign out on it.
  - It passes the token the failed request carried (read back from its `Authorization` header)
    to `onUnauthorized`, so a request that raced a refresh is retried with the new token.
  - The retry goes to `next`, the handler inside it, not to the client: through the client it
    would pass the authentication middleware again. The refresh call goes through a client (or a
    request marked to skip it) without this middleware, so a 401 for the refresh cannot start
    another refresh.
  - Which requests are public (sign-in, sign-up, refresh) is an explicit list or a separate
    client, not "the token is null". A protected request with no token fails at once with
    `UnauthorizedException` instead of going out to collect a 401.
  - Concurrent requests share one refresh future; never serialize every request through the
    middleware to avoid duplicate refreshes.
- **Retry**: only requests that are safe to repeat (`GET`, `HEAD`, `PUT`, `DELETE`, or a `POST`
  with an `Idempotency-Key` the server honours): a retried `POST` after a 500 or a timeout can
  create the order twice. Only for timeouts, network errors, 408, 429 and 5xx; never for 4xx or a
  parsing error. Wait longer each time (doubling, with some randomness), honour `Retry-After` on
  429 and 503, stop after a few attempts, and skip streaming responses (SSE).
- **Side effects**: a middleware may report to a controller (online after a response, offline on a
  network error) and rethrow; it never swallows the error.
- **Headers from memory**: values added to every request (the selected store, the warehouse) are
  read once and kept in memory, not parsed from preferences on every request.
- **Logging**: log the method, the path, the status and the time, never the `Authorization`
  header, cookies or bodies with personal data.

### Feature level: config widgets

A feature's config widget (`example_config_widget.dart`) initializes and provides its controllers:

- In `initState` it reads `DependenciesScope.of(context)`, builds the repository from the shared
  services and creates the controllers. It disposes them in `dispose`.
- It exposes itself through an `InheritedWidget`:

```dart
class ExampleConfigInhWidget extends InheritedWidget {
  const ExampleConfigInhWidget({super.key, required this.state, required super.child});

  static ExampleConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<ExampleConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'ExampleConfigInhWidget was not found in element tree');
    return (widget as ExampleConfigInhWidget).state;
  }

  final ExampleConfigWidgetState state;

  @override
  bool updateShouldNotify(ExampleConfigInhWidget old) => false; // prevent unnecessary rebuilds
}
```

- If the project has authentication, the config widget listens to the authentication controller
  and initializes controllers when the state becomes authenticated:

```dart
void _authenticationListener() {
  if (_controllersCreated) return;
  if (_authenticationController.state case Authentication$AuthenticatedState()) {
    _controllersCreated = true;
    // create the controllers that need a signed-in user
  }
}
```

### Reaching feature dependencies

Widgets below the config widget use `ExampleConfigInhWidget.of(context)`:

```dart
class _ExampleMobileWidgetState extends State<ExampleMobileWidget> {
  late final _exampleInhWidget = ExampleConfigInhWidget.of(context);
  late final _exampleDataController = _exampleInhWidget.exampleDataController;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _exampleDataController,
    builder: (context, child) => /* UI from the controller's state */,
  );
}
```

### Interfaces and constructor injection

- Repositories and data providers always have an interface and an implementation:
  `abstract interface class IExampleRepository` and `final class ExampleRepositoryImpl implements
  IExampleRepository` (`implements` an interface, not `extends` a base class). Tests replace them,
  and a second implementation (another backend, a cache) needs nothing above it to change; the
  interface costs a few lines, not a noticeable part of a feature.
- Models, controllers and widgets get no interface by default: until there is a second
  implementation it is code that does nothing.
- Dependencies come through constructors:

```dart
// A repository implementation receives its services.
ExampleRepositoryImpl({required final ApiClient apiClient}) : _apiClient = apiClient;

// A controller receives the repository interface.
ExampleController({required final IExampleRepository exampleRepository, /* ... */})
```

- Widgets get app-wide services from `DependenciesScope` and feature controllers from the feature
  scope. A widget never builds a repository itself and never holds one (see
  `docs/rules/architecture.md`).
- Never create a dependency inside a controller: it cannot be replaced in a test.

## Examples

Whole files, one per block; put each where the layout above says and adjust the imports.

### `context_extension.dart`

```dart
// file: context_extension.dart
import 'package:flutter/widgets.dart';

import 'app_navigator.dart';
import 'app_pages.dart';
import 'dependencies.dart';

/// `context.ext`: the app's shortcuts, kept out of [BuildContext]'s own members.
extension BuildContextX on BuildContext {
  /// The app's shortcuts for this context.
  AppContext get ext => AppContext(this);
}

/// Shortcuts over a [BuildContext]. An extension type: compiled away, nothing is allocated.
extension type AppContext(BuildContext _context) {
  /// The app-wide dependencies.
  Dependencies get dependencies => DependenciesScope.of(_context);

  /// Shows [page] on top of the stack.
  void push(AppPage page) => AppNavigator.push(_context, page);

  /// Removes the top page.
  void pop() => AppNavigator.pop(_context);
}
```

### `initialization.dart`

```dart
// file: initialization.dart
import 'dart:async';
import 'dart:developer' as developer;

import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'dependencies.dart';

/// One named step of startup; the steps run in order and fill in [Dependencies].
typedef InitializationStep = FutureOr<void> Function(Dependencies dependencies);

/// Sets up error reporting, then runs [steps] in order while the native splash stays on screen.
///
/// The first frame is held back until the first `runApp` after this has drawn one.
Future<Dependencies> initializeApp({
  required Map<String, InitializationStep> steps,
  void Function(int percent, String step)? onProgress,
}) async {
  final binding = WidgetsFlutterBinding.ensureInitialized()..deferFirstFrame();
  try {
    _catchErrors();
    Controller.observer = const LoggingControllerObserver();
    return await _runSteps(steps, onProgress);
  } finally {
    binding.addPostFrameCallback((_) => binding.allowFirstFrame());
  }
}

Future<Dependencies> _runSteps(
  Map<String, InitializationStep> steps,
  void Function(int percent, String step)? onProgress,
) async {
  final dependencies = Dependencies();
  var done = 0;
  for (final MapEntry(key: name, value: step) in steps.entries) {
    onProgress?.call(done * 100 ~/ steps.length, name);
    developer.log('Initialization: $name', name: 'app');
    try {
      await step(dependencies);
    } on Object catch (error, stackTrace) {
      // The step's name travels with the error; the stack trace stays the original one.
      Error.throwWithStackTrace(StateError('Initialization failed at "$name": $error'), stackTrace);
    }
    done++;
  }
  onProgress?.call(100, 'Done');
  return dependencies;
}

void _catchErrors() {
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    _report(details.exception, details.stack ?? StackTrace.current, 'Flutter error');
    presentError?.call(details); // keep the red screen and the console output in debug
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    _report(error, stackTrace, 'Uncaught error');
    return true;
  };
}

/// Sends an error to the log; the crash reporter goes here too.
void _report(Object error, StackTrace stackTrace, String hint) =>
    developer.log(hint, error: error, stackTrace: stackTrace, name: 'app', level: 1000);

/// Reports what every controller does: its state transitions to the log, its errors as errors.
final class LoggingControllerObserver implements IControllerObserver {
  const LoggingControllerObserver();

  @override
  void onCreate(Controller controller) {}

  @override
  void onDispose(Controller controller) {}

  @override
  void onHandler(HandlerContext context) {}

  @override
  void onStateChanged<S extends Object>(StateController<S> controller, S prevState, S nextState) =>
      developer.log('${controller.name}: $prevState -> $nextState', name: 'controller');

  @override
  void onError(Controller controller, Object error, StackTrace stackTrace) =>
      _report(error, stackTrace, '${controller.name} failed');
}
```

### `dependencies.dart`

```dart
// file: dependencies.dart
import 'package:flutter/widgets.dart';

import 'example_repository.dart';

/// App-wide services, created once at startup and shared through [DependenciesScope].
class Dependencies {
  /// The shared service repositories are built on (an API client, a database, ...).
  late final ExampleService exampleService;

  /// Wraps [child] so every descendant can reach these dependencies.
  Widget inject({required Widget child, Key? key}) =>
      DependenciesScope(dependencies: this, key: key, child: child);
}

/// Exposes [Dependencies] to the widget tree.
class DependenciesScope extends InheritedWidget {
  const DependenciesScope({required this.dependencies, required super.child, super.key});

  final Dependencies dependencies;

  /// The dependencies, or `null` when there is no scope above [context].
  static Dependencies? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DependenciesScope>()?.dependencies;

  /// The dependencies; throws when there is no scope above [context].
  static Dependencies of(BuildContext context) =>
      maybeOf(context) ?? _notFoundInheritedWidgetOfExactType();

  static Never _notFoundInheritedWidgetOfExactType() => throw ArgumentError(
    'DependenciesScope was not found in the widget tree. '
    'Wrap the app with Dependencies.inject(child: ...).',
  );

  // Dependencies never change after startup, so nothing needs to rebuild.
  @override
  bool updateShouldNotify(covariant DependenciesScope oldWidget) => false;
}
```
