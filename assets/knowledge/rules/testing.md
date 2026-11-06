---
name: testing
description: "Tests: mocks of interfaces with mocktail, fakes, data providers (HTTP client, drift, shared_preferences), widget tests, sharding, and time-dependent code with fakeAsync."
---

# Testing

## Rules

- Test what the user or the caller sees. Replace the dependencies of the class under test, never
  the class itself: stub them per test with `mocktail` (see "Mocks with mocktail"), or use an
  in-memory fake where the test needs state across calls.
- Mock the interface a class depends on (`IAuthService`), never its implementations
  (`AuthRemoteService`): the class under test only knows the interface. Keep implementations
  `final`; do not loosen them to make them mockable. See "What to mock".
- Test-only code in `lib/` is marked `@visibleForTesting`. See "Test-only code".
- Integration tests use `package:integration_test` and run with `flutter test integration_test/`;
  on the web, only `flutter drive` runs them. See "Integration tests".
- Code that cannot be tested is the problem, more than code without tests: see "Testability".
- A test never waits for real time: no `sleep`, no `Future.delayed` to "let it finish". Time is
  faked: `fakeAsync` in a unit test, `tester.pump(duration)` in a widget test.
- Code that reads the time uses `clock.now()` from `package:clock`, never `DateTime.now()`, so a
  test can move it.
- Generated test data (random names, long texts for layout tests) comes from a seeded
  `Random(42)`, passed in: a failure then happens again on the next run.
- Every test leaves nothing running: controllers disposed, streams closed, no pending timers.
- A data provider is tested against a mock of the app's own HTTP client interface (maps in, maps
  or exceptions out), never of Dio or `package:http`; drift against `NativeDatabase.memory()`,
  closed after each test; `SharedPreferencesAsync` against `InMemorySharedPreferencesAsync`. See
  "Testing the data layer".
- A slow suite is split across machines: with `flutter test --total-shards N --shard-index I` when
  test files hold many tests, by test file otherwise. See "Sharding".
- A controller is tested by the sequence of its states (`toStream()`, `emitsInOrder`,
  `isA<...>().having(...)`), not with `bloc_test`: see "Testing a controller" in
  `docs/rules/controllers.md`.

## Testability

The surest sign of bad code is not missing tests but that a test cannot be written for a component.
Each kind of trouble writing one points at a SOLID principle the code breaks:

- **The test has to change whenever anything in the app changes**: the component does too much
  (single responsibility). Split it until a test covers one reason to change.
- **Adding to the component breaks the existing tests, or merges keep conflicting**: it is changed
  by editing instead of extending (open/closed). Add new members and implementations; deprecate the
  old ones (see "Changing shared code" in `docs/rules/architecture.md`).
- **It misbehaves with a fake or a mock of its dependency**: it relies on one implementation, not
  on the contract (Liskov substitution). Any implementation of the interface must work.
- **It depends on a huge interface and uses a third of it**: the interface is too wide (interface
  segregation). Split it into small interfaces; one class can still implement several of them.
- **A dependency arrives some other way than the constructor** (a global, a service locator, a
  static instance): a mock cannot be put in its place (dependency inversion). Take the interface in
  the constructor.

## Mocks with mocktail

Writing mocks by hand is where most of the time of testing goes, and a hand-written "mini
repository" ends up testing the mock instead of the code. Use `mocktail` (no code generation; a
`dev_dependency`) and set the conditions each test needs right in the test:

```dart
class MockProductsRepository extends Mock implements IProductsRepository {}

void main() {
  late MockProductsRepository repository;

  setUp(() => repository = MockProductsRepository());

  test('load shows the first page', () async {
    when(
      () => repository.products(
        categoryId: any(named: 'categoryId'),
        query: any(named: 'query'),
        page: 1,
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => (<Product>[apple, pear], 2));
    final controller = ProductsController(productsRepository: repository);
    addTearDown(controller.dispose);
    final states = controller.toStream();

    controller.load();

    await expectLater(
      states,
      emitsInOrder(<Matcher>[
        isA<Products$ProcessingState>(),
        isA<Products$SuccessfulState>().having((s) => s.products, 'products', [apple, pear]),
        isA<Products$IdleState>(),
      ]),
    );
    verify(() => repository.products(
          categoryId: null,
          query: '',
          page: 1,
          pageSize: 50,
        )).called(1);
  });

  test('a failing page keeps the rows', () async {
    when(
      () => repository.products(
        categoryId: any(named: 'categoryId'),
        query: any(named: 'query'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenThrow(StateError('offline'));
    // ...
  });
}
```

- Give each test the data the code expects and the data it does not (empty, malformed, an error),
  then check how the code reacts: that is the point of the test.
- `when(...).thenAnswer((_) async => ...)` for a `Future`, `.thenThrow(...)` for a failure,
  `verify(...).called(n)` when the call itself is the behaviour.
- `any()` with a type of your own needs `registerFallbackValue(...)` once, in `setUpAll`.
- An in-memory fake still fits where a test needs state across calls: a repository whose `watch()`
  stream emits after a `save()`, or a widget test that drives a whole screen.
- Do not test the mock: when a test only proves that a stub returns what it was told to, delete it.

### What to mock

Mock what the class under test receives, which is an interface. A repository that takes an
`IAuthService` for the server and another for the local store is tested with two mocks of
`IAuthService`, not with mocks of `AuthRemoteService` and `AuthLocalService`:

```dart
class MockAuthService extends Mock implements IAuthService {}

void main() {
  late MockAuthService remote;
  late MockAuthService local;
  late MockInternetConnection connection;
  late AuthRepositoryImpl repository;

  setUp(() {
    remote = MockAuthService();
    local = MockAuthService();
    connection = MockInternetConnection();
    repository = AuthRepositoryImpl(remote: remote, local: local, connection: connection);
  });
  // ...
}
```

- The interface is the contract the repository relies on; a mock of it is one more implementation
  of that contract. A mock of an implementation drags that implementation's own dependencies and
  details into a test that is not about them.
- It is also the only thing that works with class modifiers: a `final` or `base` class cannot be
  implemented outside its own library, and a test is another library, so `implements
  AuthRemoteService` does not compile. An `abstract interface class` can be implemented anywhere.

### Fakes for wide interfaces

When a test needs a couple of members of a wide interface (an app's dependency container, a
platform service), extend mocktail's `Fake` and override only those. Every other member throws
`UnimplementedError`, so a test that touches something it did not set up fails loudly:

```dart
class FakeDependencies extends Fake implements Dependencies {
  FakeDependencies({required this.productsRepository});

  @override
  final IProductsRepository productsRepository;
}
```

Without mocktail, the same is a class that `implements` the interface and overrides
`noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation)`: the compiler then accepts
the missing members, and calling one throws `NoSuchMethodError`.

### Test-only code

A class or member in `lib/` that exists for tests (a base class for test containers, a constructor
that takes a clock, a reset method) is annotated `@visibleForTesting` (from `package:meta`, also in
`flutter/foundation.dart`). It stays public, but the analyzer warns
(`invalid_use_of_visible_for_testing_member`) when code outside its own library and outside the
tests names it. It is a warning, not a wall: the code still compiles and still ships, so keep
anything sensitive out of it. Mark the type, and also the constructor or member that callers use:
on a class, the analyzer reports uses of the type (`extends`, a type annotation), not a plain
constructor call.

## Testing the data layer

A data provider is tested against what it talks to: the real thing in memory when there is an
in-memory form, otherwise a mock of the app's own client.

### HTTP

Mock the client interface the provider receives (`IApiClient` in `payments_data_provider.dart`, in
`docs/rules/repositories.md`), not Dio or `package:http`. That client already decodes the body and
turns transport failures into the app's exceptions, so a test returns a map or throws, and never
builds a `Response`, a status code or bytes. Cover, for each method: the expected answer, an answer
of the wrong shape (a `FormatException`), each backend code the provider translates (its typed
exception), and an unknown code (passed on unchanged). Checked: these tests pass against the
example.

```dart
class MockApiClient extends Mock implements IApiClient {}

void main() {
  late MockApiClient client;
  late PaymentsDataProviderRemote provider;

  setUp(() {
    client = MockApiClient();
    provider = PaymentsDataProviderRemote(client: client);
  });

  When<Future<Map<String, Object?>>> whenPost() =>
      when(() => client.post(any(), body: any(named: 'body')));

  test('a receipt', () async {
    whenPost().thenAnswer((_) async => {'receipt': {'id': 'r1', 'total': 500}});
    final receipt = await provider.pay(orderId: 'o1');
    expect(receipt.total, 500);
    verify(() => client.post('/payments', body: {'order_id': 'o1'})).called(1);
  });

  test('a receipt of the wrong shape is a FormatException', () async {
    whenPost().thenAnswer((_) async => {'receipt': {'id': 1}});
    await expectLater(provider.pay(orderId: 'o1'), throwsFormatException);
  });

  test('insufficient_funds becomes InsufficientFundsException', () async {
    whenPost().thenThrow(const RejectedException(code: 'insufficient_funds'));
    await expectLater(provider.pay(orderId: 'o1'), throwsA(isA<InsufficientFundsException>()));
  });

  test('an unknown code passes on unchanged', () async {
    const rejected = RejectedException(code: 'order_closed');
    whenPost().thenThrow(rejected);
    await expectLater(provider.pay(orderId: 'o1'), throwsA(same(rejected)));
  });
}
```

### Drift

Open the database on `NativeDatabase.memory()` (`package:drift/native.dart`): every test gets a
fresh, empty database and no file. The database class takes its `QueryExecutor` through the
constructor for this (the `AppDatabase.memory()` of "Startup and creating dependencies" in
`docs/rules/dependencies.md` is the same thing). Create it in `setUp` and close it after the test:

```dart
late AppDatabase database;

setUp(() {
  database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
});
```

- Closing is what "Every test leaves nothing running" asks. Drift also counts open instances of a
  database class: creating one while another is still open prints a warning ("created the
  database class ... multiple times") in debug builds (drift 2.35.3, `db_base.dart`). Close the
  database instead of setting `driftRuntimeOptions.dontWarnAboutMultipleDatabases`.
- Test the repository's queries and its `watch()` streams against this database; mock the
  repository, not the database, in controller tests.

### shared_preferences

`SharedPreferencesAsync` (and `SharedPreferencesWithCache`, which is built on it) talks to
`SharedPreferencesAsyncPlatform.instance`. In a test, set that to the in-memory store before
creating the preferences; `shared_preferences_platform_interface` goes to `dev_dependencies`,
since the test imports it:

```dart
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

setUp(() {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(
    <String, Object>{'theme.mode': 'dark'},
  ); // or InMemorySharedPreferencesAsync.empty()
});
```

- A new store in every `setUp` keeps the tests independent.
- `SharedPreferences.setMockInitialValues` fills the store of the legacy `SharedPreferences`
  class only. `SharedPreferencesAsync` ignores it, and its constructor throws `StateError: The
  SharedPreferencesAsyncPlatform instance must be set.` when nothing set the instance. Checked
  with shared_preferences 2.5.6, together with a test of `ThemeDataProviderLocal`
  (`preferences_entry.dart` in `docs/rules/repositories.md`) on the in-memory store.

## Widget test

Test behaviour the user sees, not the widget tree layout.

### Steps

1. Create `test/<feature>/<widget>_test.dart` next to the other tests of the feature.
2. Replace services with in-memory fakes of the repository interfaces (`IFooRepository`), and pass
   them to the real controller. Do not mock the widget itself.
3. Wrap the widget in `MaterialApp` with `Localization.localizationsDelegates` and the app theme,
   so `Localization.of(context)` and the theme extensions work. Set the test window size
   (`tester.view.physicalSize`) to the screen size the widget targets, and reset it in `addTearDown`.
4. `await tester.pumpWidget(...)`, interact with `tester.tap` and `tester.enterText`, then
   `await tester.pump()` or `pumpAndSettle()`.
5. Assert on visible text and state: `find.text`, `find.byType`, the fake repository's calls.
6. Cover the empty, loading, error and filled states, and one failing action.

### Rules

- Dispose controllers in `tearDown`; leave no timers or streams open.
- Use `tester.runAsync` for real I/O such as assets or processes.
- Run with `flutter test test/<feature>/`.

## Integration tests

An integration test runs the real app on a device, an emulator, the desktop or a browser. It is
written with the widget test API (`testWidgets`, `WidgetTester`, `find`), from the SDK's
`integration_test` package (`integration_test: sdk: flutter` under `dev_dependencies`), and lives
in `integration_test/`.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signs in', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('email')), 'a@b.c');
    await tester.enterText(find.byKey(const ValueKey('password')), 'longenough');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
}
```

There are two commands, and the test file is the same for both:

- `flutter test integration_test/ -d <device>`: the direction Flutter develops, and the same runner
  as unit and widget tests. Use it on Android, iOS, macOS, Windows and Linux. It does not run on the
  web: the tool stops with "Web devices are not supported for integration tests yet."
- `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/<name>_test.dart`:
  the older command. A driver script on the host talks to the app; `test_driver/integration_test.dart`
  is two lines:

```dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
```

  `flutter drive` is still needed for three things:
  - the web. Start `chromedriver --port=4444` in another terminal, then pass `-d chrome` (or
    `-d web-server`, headless by default);
  - screenshots saved on the host: `binding.takeScreenshot(name)` in the test, and
    `integrationDriver(onScreenshot: ...)` from `integration_test_driver_extended.dart` in the driver;
  - performance numbers: `binding.traceAction(...)` or `binding.watchPerformance(...)` in the test,
    run with `--profile`; the driver's `writeResponseData` writes them to `build/`.

What integration tests need besides the widget test API:

- **Finding things**: `find.byKey`, `find.text`, and `find.bySemanticsIdentifier('sign-in')` for
  `Semantics(identifier: 'sign-in')`. An identifier is not shown or read to users; it becomes
  `resource-id` on Android, `accessibilityIdentifier` on iOS and `flt-semantics-identifier` on the
  web, so the same id serves Flutter tests, Appium or XCUITest, and browser tests. Never put test
  ids into labels a screen reader reads.
- **System dialogs** (a permission, a notification prompt) are native: Dart code cannot tap them.
  Grant the permission before the run (`adb shell pm grant <package> android.permission.CAMERA`,
  `xcrun simctl privacy booted grant camera <bundle id>`), drive the dialog with a package that
  automates the platform (`patrol`), or keep permissions behind an interface that most tests
  replace.
- **Screenshots** of a widget against a stored image: `matchesGoldenFile` in a widget test
  (`alchemist` adds themes and platforms). To save images:
  - Of the whole app on Android and iOS: `binding.takeScreenshot(name)`, after
    `binding.convertFlutterSurfaceToImage()` once on Android. The bytes reach your computer only
    through `flutter drive` and the driver's `onScreenshot` (above).
  - Of the whole app, or of one widget, anywhere (Windows, macOS, Linux, the web): wrap it in a
    `RepaintBoundary`, pump, then `boundary.toImage(pixelRatio: ...)` and
    `image.toByteData(format: ImageByteFormat.png)`, and `dispose()` the image afterwards. A
    widget test runs this inside `tester.runAsync`. The image holds only what Flutter draws: no
    platform views, no system bars.
  - Writing the PNG with `File('screenshots/app.png')` works when the test runs on your computer
    (desktop). On a phone the test runs on the device, where a relative path is not your project:
    send the bytes back through `flutter drive` instead.
- **Coverage**: `flutter test --coverage` writes `coverage/lcov.info`.
- **An app that can be tested**: dependencies come from `main` and can be replaced, so every test
  builds a fresh set; singletons and globals make tests share state and force one test per
  process (see "Testability").
- Shader warm-up runs (`--cache-sksl`, `--write-sksl-on-exit`) are gone from the Flutter tool:
  Impeller, the default renderer on iOS and Android, compiles its shaders when the app is built.

Do not write new tests with `package:flutter_driver` (`FlutterDriver`, `find.byValueKey` from a
separate process): `integration_test` replaces it.

## Sharding

`flutter test --total-shards N --shard-index I` runs one part of the suite, so N CI jobs run it in
parallel. `I` counts from 0 to N - 1; an index outside that range is a usage error. The split is by
test, not by file: checked, with two shards the first and second test of one file ran on different
shards, so every shard still loads and compiles every test file, and a shard that gets no test
fails the job. Use the flags when test files hold many tests each; otherwise split by file: see
"Sharding tests" in `docs/rules/tooling.md`.

## Time in unit tests: fakeAsync

Code with `Timer`, `Future.delayed`, debounce, throttle, periodic streams or timeouts is tested in a
plain `test` inside `fakeAsync` (`package:fake_async`, a dev dependency). Nothing waits: time only
moves when the test moves it, so a five-day timeout runs in microseconds.

### Moving time

- `async.elapse(duration)`: moves the fake clock forward and fires every timer due within it,
  running the microtasks before and after each one. `async.elapse(Duration.zero)` lets pending
  futures finish without moving time past anything.
- `async.flushMicrotasks()`: runs the scheduled microtasks (completed futures, `then` callbacks)
  without moving time; timers do not fire.
- `async.flushTimers()`: moves time until no timer is left, including timers the fired ones
  schedule. A periodic timer would run forever, so it throws after `timeout` (one hour of fake
  time by default); pass `flushPeriodicTimers: false` to stop when only periodic timers remain.
- `async.pendingTimers`: the timers still scheduled; at the end of a test it should be empty.

### Futures

The callback of `fakeAsync` is synchronous: never `await` inside it, since nothing completes until
time moves and the test would hang. Register the expectation first, then move time:

```dart
test('a closed queue rejects new work', () {
  fakeAsync((async) {
    final queue = EventQueue();
    expectLater(queue.add(() {}), completes);
    expectLater(queue.close(), completes);

    async.elapse(Duration.zero);

    expect(queue.isClosed, isTrue);
    expect(() => queue.add(() {}), throwsStateError);
  });
});
```

`expectLater(future, completes)` (or `throwsStateError`, `completion(value)`) fails the test if the
future has not done so by the end of the `fakeAsync` call.

A future that belongs to the root zone does not move with fake time. `cancel()` on a subscription
whose `StreamController` has no `onCancel` returns such a future, already completed: its callbacks
wait for the real microtask queue, which `flushMicrotasks` and `elapse` do not run. So code that
awaits that `cancel()` stalls inside `fakeAsync`, and so does an `await for` loop left by an
error or a `break`, which awaits it. Checked: inside `fakeAsync`, a `then` on that future had not
run after `flushMicrotasks` and `elapse`, and ran at once when the controller had an `async`
`onCancel`. Test such code with a plain `async` test, or give the fake's controller
`onCancel: () async {}`.

### Timers and debounce

```dart
test('the search runs 300 ms after the last keystroke', () {
  fakeAsync((async) {
    final searches = <String>[];
    final debouncer = Debouncer(const Duration(milliseconds: 300), searches.add);

    debouncer('f');
    async.elapse(const Duration(milliseconds: 200));
    debouncer('fl');
    async.elapse(const Duration(milliseconds: 299));
    expect(searches, isEmpty);

    async.elapse(const Duration(milliseconds: 1));
    expect(searches, <String>['fl']);
    expect(async.pendingTimers, isEmpty);
  });
});
```

### The clock

Inside `fakeAsync`, `clock.now()` from `package:clock` follows the fake time, starting at
`initialTime` (the real time when it is not given). `DateTime.now()` does not: code under test
must read `clock.now()`.

```dart
test('a session expires after five days', () {
  fakeAsync((async) {
    final session = Session(startedAt: clock.now());

    async.elapse(const Duration(days: 4));
    expect(session.isExpired, isFalse);

    async.elapse(const Duration(days: 1));
    expect(session.isExpired, isTrue);
  }, initialTime: DateTime(2026, 1, 1));
});
```

`clock` has helpers for dates relative to now: `clock.daysAgo(3)`, `clock.monthsFromNow(1)`,
`clock.yearsFromNow(5)`. `async.getClock(initialTime)` gives a second clock that starts at another
time and moves with the same fake time.

### Rules

- `fakeAsync` is for `test`. A `testWidgets` test already runs on fake time: move it with
  `tester.pump(duration)`, and put real asynchronous work (files, processes, isolates) inside
  `tester.runAsync`.
- Real I/O (files, sockets, processes, `Isolate.run`) does not run on fake time: fake it behind
  its repository interface instead of calling it inside `fakeAsync`.
- Add `fake_async` and `clock` with `flutter pub add` (see `docs/rules/package-freshness.md`):
  `clock` to `dependencies` when code reads it, `fake_async` to `dev_dependencies`.
