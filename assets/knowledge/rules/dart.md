---
name: dart
description: "Dart language: errors and exceptions, waiting for several futures, class modifiers, patterns for switch, if-case, destructuring and JSON, records, collections, text length; cached futures, debug-only code and sorting."
---

# Dart

## Rules

- Match and take values apart with patterns (Dart 3): a `switch` over a sealed type, `if (x case
  ...)` for one shape, destructuring in `final` / `var` and in `for`. No chains of `is` checks and
  casts.
- A `switch` over a `sealed` class or an enum lists every case and has no `_` arm: the compiler
  then reports the case a new variant forgot.
- Throw an `Exception` for a failure the caller cannot check for in advance (the network, a file,
  the server's answer, input) and an `Error` only for a bug. Throw a named type, never
  `Exception('text')`, a `String` or a map, and never catch an `Error` subtype to recover. See
  "Errors and exceptions".
- Run independent futures at once with `.wait` on a record (`await (a(), b()).wait`), which keeps
  their types and every error; not `Future.wait`, and never start several futures and then await
  them one by one. See "Waiting for several futures".
- Pick a class modifier by the role: `abstract interface class` for a contract (a repository, a
  data provider), `final class` for an implementation, a state or an exception that nothing
  extends, `sealed class` for a closed family, `base` only when every subtype must inherit the
  code. See "Class modifiers".
- A method a subclass in another file implements is public and marked `@protected` and
  `@visibleForOverriding`, never private: a private member cannot be implemented from another
  library. See "Hooks for subclasses".
- Parse JSON with map patterns (`if (json case {'id': final int id})`), not `json['id'] as int`.
  Write the parsing by hand: no `json_serializable` (or freezed's `fromJson`). A pattern is as
  short as the annotations it replaces, and there is no generator to run after every change.
- `Object` is any value except `null`; `Object?` is any value at all. `dynamic` is not a type but
  the absence of type checks: calls on it compile and fail at run time. Use `Object?` (JSON is
  `Map<String, Object?>`) and narrow it with patterns; `dynamic` only for rare JS interop.
- No `!` after a null check of a field or getter: bind the value with a pattern or a local
  `final`. See "Null checks without `!`".
- A record is for a few values returned together from one function; anything with behaviour, docs
  per field, or a life beyond one call is a `final class`. See "Records".
- Iterate with `for (final x in xs)`, not `forEach` with a function literal; copy a list with
  `List.of` or `[...xs]`, not `List.from`; never change a collection the code did not create (a
  `const []` default throws on `add`). See "Collections".
- Count, limit and cut text the user sees with `characters` (grapheme clusters), not `length` and
  `substring`, which count UTF-16 code units. See "Strings and text length".
- A function that never returns normally (it always throws, calls `exit`, or ends the isolate with
  `Isolate.exit`) returns `Never`, not `void`. See "`Never`".
- In UI code, check the platform with `defaultTargetPlatform` (or `Theme.of(context).platform`) and
  the web with `kIsWeb`. Code that needs `dart:io` or a JS API is split by a conditional import,
  and only its `dart:io` file uses `Platform.isAndroid` and the like: `Platform` is unavailable on
  the web. See "Platform-specific code". Tricks for detecting the web break: `identical(0, 0.0)` is
  `true` with dart2js but `false` with dart2wasm (checked), and `dart.library.js_util` is not
  defined under Wasm; `kIsWeb` reads `dart.library.js_interop`, which both define.
- Public APIs get `///` doc comments. The first sentence is a short summary that ends with a
  period, then a blank line before any detail. Say what the code cannot: why, when, what the
  caller must know. Do not repeat the name or the signature ("Gets the name" on `name`); document
  a getter or its setter, not both; refer to parameters and members as `[name]`.
- Return `Future<void>`, not `FutureOr<void>`: a caller must handle both cases, so the union gives
  it nothing. A callback parameter is the one place for `FutureOr<void> Function()`: it accepts
  both `() {}` and `() async {}`, where `Future<void> Function()` rejects a plain `void` function.
- An error that is not awaited inside a `try` goes to the zone, not to the `catch`. In a Flutter app
  the root handlers report it (`PlatformDispatcher.instance.onError`); do not wrap code in zones
  to catch errors. See "Zones".
- A `Future` kept in a field (`late final`, `??=`) keeps its failure too: every later caller gets
  the same error. Clear it on failure when a retry should run again (`LazyFuture`), and never
  start a `Future` in a constructor that nobody awaits. See "Cached futures".
- Code only for debug builds goes in `assert(() { ...; return true; }())` or `if (kDebugMode)`.
  See "Debug-only code".
- A comparator returns `a.compareTo(b)`, never `a - b`, and `List.sort` is not stable: break ties
  on a second key. See "Sorting".

## Zones

Every piece of async code runs in a zone. `main` runs in `Zone.root`; `runZoned` and
`runZonedGuarded` make a child of the current zone. A callback (`then`, `listen`, a `Timer`, a
microtask) runs in the zone where it was registered, not where the `Future` or `Stream` was
created: a stream's `onData` runs in the zone that called `listen`.

Uncaught errors:

- `try`/`catch` catches an error from async code only when the code is `await`ed inside the `try`.
  An unawaited `Future` that fails, or an error thrown in a `listen` callback, is uncaught.
- An uncaught error goes to the nearest zone with an error handler (`runZonedGuarded`, or
  `ZoneSpecification(handleUncaughtError:)`). A zone made by `runZoned` without one passes it to
  its parent; the root zone hands it to the platform (`PlatformDispatcher.instance.onError` in
  Flutter, the console in a script).
- Errors do not cross error zones. A `Future` that fails in one guarded zone and is listened to in
  another never delivers the error to that listener: the first zone's handler gets it, and the
  listener waits forever. Create and await a future in the same error zone.
- A guarded zone keeps running after it catches an error, unlike a `try` block.

In a Flutter app the root handlers in `main` replace a zone around `runApp` (see "Uncaught errors"
in `docs/rules/dependencies.md`). If a zone is used anyway, `WidgetsFlutterBinding.ensureInitialized()`
and `runApp` must run in the same zone, or Flutter warns of a zone mismatch.

Zones also carry values and replace a few core functions for the code they run:

- `runZoned(body, zoneValues: {#requestId: id})`, read with `Zone.current[#requestId]`. This is how
  `package:clock` (`withClock`) and `fakeAsync` swap the time for a test. In app code, pass
  parameters instead: a zone value is a hidden global.
- `ZoneSpecification(print: ...)` captures `print` (in a test of a script that prints), and
  `createTimer`, `scheduleMicrotask` and `run` hooks wrap timers, microtasks and every callback,
  for profiling or tracing async work.

## Errors and exceptions

`Error` and `Exception` say whose fault a failure is. An `Error` is a bug the calling code could
have avoided: a condition documented with "must" or "must not" that it could check before the
call (`ArgumentError`, `StateError`, `RangeError`, `UnsupportedError`). A failure whose cause is
outside the program and cannot be checked first (the network, a file, the server's answer, user
input) is an `Exception`; the `Error` class doc says the same ("If the conditions are not
detectable before calling a function, the called function should not throw an `Error`"). How the
data layer and the controllers handle each is in "Errors" in `docs/rules/repositories.md` and
"Expected and unexpected errors" in `docs/rules/controllers.md`.

- Throw only subtypes of `Exception` or `Error`, never a `String`, a map or a record (the
  `only_throw_errors` lint). `throw Exception('text')` creates the private `_Exception`
  (checked), which no `on` clause can tell apart from any other: give a failure that code reacts
  to a named type (`final class XException implements Exception`) with a `toString()`, and use
  `FormatException` for bad input and `TimeoutException` for a timeout.
- A class that `extends Error` records its stack trace when it is first thrown
  (`error.stackTrace`); an `Exception`, or a class that only `implements Error`, records none
  (checked). The trace of an exception exists only in `catch (error, stackTrace)`: bind it
  wherever the error is logged or wrapped, and wrap with `Error.throwWithStackTrace`.
- Do not catch an `Error` subtype by name (`on StateError`, `on TypeError`) to carry on: that hides
  a bug, and the `avoid_catching_errors` lint reports it (checked). Only the places that catch
  everything do, with `on Object`: the controller's action and `handle`, and the root handlers.
  The one exception is an `Error` that only wraps real failures, `ParallelWaitError` (see "Waiting
  for several futures"), caught with an `// ignore:` comment that says why.
- `on` clauses are tried in order, so the specific type goes before its supertype. With
  `on Exception` first, a later `on FormatException` never runs; the analyzer warns
  `dead_code_on_catch_subtype` (checked).

## Waiting for several futures

```dart
final (profile, unread) = await (repository.profile(), repository.unreadCount()).wait;
```

- `.wait` on a record of futures (Dart 3) runs them at once and keeps each type. On a list of
  futures of one type, `await futures.wait` returns a `List<T>`.
- `Future.wait([...])` over futures of different types returns `List<Object>` (checked). When
  several fail, it throws the first error and drops the others: they reach neither the `catch`
  nor the zone (checked). By default it waits for all of them before it fails
  (`eagerError: false`).
- When any future fails, `.wait` throws a `ParallelWaitError` that holds every result (`values`,
  `null` where one failed) and every failure (`errors`, each an `AsyncError` with its own stack
  trace). It is an `Error`, so a controller would report an expected failure inside it as a bug:
  catch it and rethrow the real failure as itself (`profile_screen_data.dart` in Examples; tested:
  a `StateError` or `FormatException` arrives as itself, with its own stack trace).
- Never start futures and then await them one after another:
  `final a = slow(); final b = failsFast(); (await a, await b)`. When `b` fails while the code is
  still waiting for `a`, nothing listens to `b` yet: its error is reported as uncaught to the zone
  (and the crash reporter) and is then caught as well (checked: both happened).
- `Future.wait` is fine where every future catches its own errors, as in "Several services behind
  one interface" in `docs/rules/architecture.md`.

## Class modifiers

The restrictions apply to code in other libraries. A library is a file with its `part` files; the
rules use no `part`, so here it is one file.

| Declaration | Construct | Extend | Implement | Use for |
| --- | --- | --- | --- | --- |
| `abstract interface class` | no | no | yes | a contract: a repository, a data provider, a service |
| `final class` | yes | no | no | implementations, states, exceptions that nothing extends |
| `sealed class` | no | no | no | a closed family, switched over exhaustively |
| `base class` | yes | yes | no | a base whose code every subtype must inherit (`ExpectedException`) |
| `interface class` | yes | no | yes | rarely: a concrete class others may only reimplement |
| `mixin class` | yes | yes | yes | a class that is also mixed in with `with` |

- A subtype of a `base` or `final` class must itself be `base`, `final` or `sealed`, inside its
  own library too (`subtype_of_base_or_final_is_not_base_final_or_sealed`, checked). There, such
  a subtype may still extend or implement a `final` class.
- Every case of a `sealed` class is declared in its library; another file cannot add one
  (checked). That is why a `switch` over it can be checked for exhaustiveness.
- A test is another library, so it cannot implement a `final` or `base` class: mock the
  `abstract interface class` (see "Mocks with mocktail" in `docs/rules/testing.md`).

## Hooks for subclasses

A private name belongs to its library: `_write` declared in another file is a different name. So
a private abstract member of a base class cannot be implemented by a subclass in another file. It
compiles with no diagnostic, and the call from the base class throws `NoSuchMethodError` at run
time (checked). Make the hook public and mark it with the `package:meta` annotations, which
`package:flutter/foundation.dart` re-exports:

```dart
abstract base class Exporter {
  const Exporter();

  /// Exports [rows]: the same checks for every exporter, then [write].
  @nonVirtual
  Future<void> export(List<String> rows) async {
    if (rows.isEmpty) return;
    await write(rows);
  }

  /// Writes [rows] to the target. Called by [export] only.
  @protected
  @visibleForOverriding
  Future<void> write(List<String> rows);
}
```

- A call to `write` through `Exporter` from outside a subclass is reported
  (`invalid_use_of_protected_member`, `invalid_use_of_visible_for_overriding_member`; checked), and
  `@nonVirtual` stops a subclass from overriding `export`. A call through the subclass's own type
  is reported only when its override repeats the annotations.
- Where no shared code is needed, an `abstract interface class` and composition are simpler (see
  "Interfaces and constructor injection" in `docs/rules/dependencies.md`).

## Enums

An enum can carry fields, getters, methods and interfaces (`order_status.dart`):

- A value the outside world sees (JSON, the database) is a field, `code`, and parsing looks it up
  in a map built once from `values`; never `toString().split('.')` or `index`, which change when
  a value is renamed or reordered. An unknown code from a newer server becomes `null` or a
  fallback, not a crash. `values.byName(name)` throws `ArgumentError` on an unknown name;
  `values.asNameMap()[name]` returns `null`.
- Behaviour per value is an exhaustive `switch` expression in a getter, not hand-written `map` /
  `maybeMap` helpers: a new value then fails to compile wherever it is not handled.
- Interfaces are implemented, not mixed in: `enum X implements Comparable<X>`. On Dart 3,
  `with Comparable<X>` fails ("can't be used as a mixin").
- Leave `toString()` alone (it is for logs) and keep user-facing labels out of the enum: they are
  localized, so the widget maps the value to `Localization.of(context)` text with a `switch`.

```dart
// file: order_status.dart
/// The status of an order, as the server sends it.
enum OrderStatus implements Comparable<OrderStatus> {
  pending('pending'),
  paid('paid'),
  shipped('shipped'),
  cancelled('cancelled');

  const OrderStatus(this.code);

  /// The value stored and sent; separate from the Dart name, so renaming a value changes no data.
  final String code;

  static final Map<String, OrderStatus> _byCode = <String, OrderStatus>{
    for (final status in values) status.code: status,
  };

  /// The status for [code], or `null` for a code this version does not know.
  static OrderStatus? tryParse(String? code) => _byCode[code];

  /// Whether nothing can happen to the order any more.
  bool get isFinal => switch (this) {
    shipped || cancelled => true,
    pending || paid => false,
  };

  /// Declaration order: `pending` before `paid` before `shipped`.
  @override
  int compareTo(OrderStatus other) => index.compareTo(other.index);
}
```

## Value types with extension types

An extension type wraps a value with its own API at no run-time cost: it is the wrapped value.
Two uses that come up again and again (`value_types.dart` in Examples):

- **A date without a time** (a birthday, a due date). A `DateTime` always has a time and a time
  zone: a birthday stored as local midnight and sent as UTC moves to the day before for users east
  of Greenwich. `Date` keeps only the day: every constructor drops the time, so two dates of the
  same day are equal, and it is stored and sent as `YYYY-MM-DD`. Build it in UTC, so day
  arithmetic does not meet daylight saving time. Wrapping a `DateTime` as it is
  (`Date.from(now) implements DateTime`) keeps the hours, and two "dates" of one day differ.
- **A set of flags** in one `int` (`PasswordIssues`): constants `1 << n`, `|` to combine,
  `contains` to test. No list, no allocation, and the whole set compares and stores as a number.

## `Never`

`Never` is the bottom type: no value has it, so a function that returns `Never` cannot complete.
`void` says "completes and returns nothing"; `Never` says "does not complete normally".

```dart
Never unreachable(String message) => throw StateError(message);

int next(int? value) {
  if (value == null) unreachable('value is missing');
  return value + 1; // value is promoted to int: the line above cannot fall through
}
```

- The analyzer knows the code after a call cannot run: it promotes types (as above) and marks
  anything after the call as dead code.
- A body that could still return is a compile error ("the body might complete normally"), so the
  type also checks the function itself.
- Use it for helpers that throw (`fail`, `unauthorized`), for `exit(code)` wrappers, and for an
  isolate's last call (`Isolate.exit`).

## Names with `$`

`$` is a legal character in Dart names; it has three uses here:

- **A separator for hierarchy**: `ProductsScreen$Filters`, `_ProductsScreen$Filters$Chips` for the
  parts of one screen; `Products$IdleState` for the cases of a sealed class;
  `ChatRepository$HttpImpl$V1` for an implementation and its version. A double click selects one
  part of the name.
- **A leading `$` for helpers** not meant for general use: `$initializeApp`, `$MutableDependencies`.
  With `_$` it marks the backing field of a cached value:

```dart
Future<Settings>? _$settings;
Future<Settings> settings() => _$settings ??= _repository.fetchSettings();
```

  This keeps a failed fetch as well: see "Cached futures".

- **Generated code** uses `_$` too (`_$ExampleFromJson`, freezed's `_$Example`); do not hand-write
  names that could collide with it.

## Cached futures

A `Future` stored in a field shares one attempt among all callers, concurrent or later: what a
start-up value or a settings fetch needs. It also stores a failure. With
`late final Future<Settings> settings = _load();` or `_$settings ??= _load()`, a failed `_load`
is the answer forever: every caller gets the same error and `_load` never runs again (checked:
two reads, one call, two errors).

- For something that can fail and should be retried (a connection, a download, a token), clear
  the field when the future fails: `LazyFuture` (in Examples) does that and still shares one
  attempt between concurrent callers (checked).
- Do not start asynchronous work in a constructor and keep the `Future` for later
  (`Client() : _ready = _connect();`). If nobody awaits it, its error is uncaught and goes to the
  zone, `PlatformDispatcher.instance.onError` in an app (checked: the guarded zone's handler got
  the error while the object was never used). Start it in a method the owner awaits (`open()`,
  `load()`), or in an initialization step (`docs/rules/dependencies.md`): constructors stay
  synchronous.
- Lazy creation is for something expensive and rarely needed (a native library, a large model),
  held by its owner; it is not a reason for a global (see `docs/rules/dependencies.md`).
- A top-level or static variable with an initializer runs it at the first read, not at startup,
  once per isolate. If the initializer throws, nothing is stored and the next read runs it again,
  as with a `late final` field that has an initializer (checked: the first read threw, the second
  returned the value): the opposite of a stored `Future`, which keeps its failure. An initializer
  that registers something (a handler, a plugin) therefore does nothing until code reads the
  variable: do that work in an initialization step.

## Debug-only code

`assert` statements are not executed in profile and release builds, and their argument is not
evaluated there. A closure called inside one runs a whole block in debug builds only:

```dart
assert(() {
  _checkSorted(items); // too slow for release
  return true;
}());
```

- Use it for checks that are too expensive or too noisy for release: an invariant over a whole
  list, a debug label, a warning in the console. The framework does the same
  (`debugCheckHasMaterial`). Never put a side effect the app needs in it.
- `if (kDebugMode) { ... }` (`package:flutter/foundation.dart`) also runs only in debug builds and
  reads more plainly; `kDebugMode` is a `const`, so the block is removed from release builds. Use
  it in Flutter code; the `assert` form works in plain Dart too (where `dart test` and
  `dart run --enable-asserts` turn asserts on).

## Sorting

- A comparator returns `a.compareTo(b)` (or `b.compareTo(a)` for descending order), never
  `a - b`: the subtraction overflows for large `int`s on native platforms. Checked:
  `[maxInt, -maxInt, 0, 5]..sort((a, b) => b - a)` gives a wrong order; with `compareTo` it is
  right.
- `List.sort` is not stable: elements that compare equal may change places (its doc; checked: 100
  records sorted on a key with three values lost their original order). When equal elements must
  keep an order, compare a second key (an id, the original index) when the first is equal, or use
  `mergeSort` from `package:collection`, which is stable.

```dart
items.sort((a, b) => switch (a.priority.compareTo(b.priority)) {
  0 => a.id.compareTo(b.id),
  final order => order,
});
```

## Collections

- **`const` collections cannot change.** A `const` list, map or set compiles with `add` or `[]=`
  and throws `UnsupportedError` at run time. The usual trap is a default value:
  `Filter({this.tags = const []})`, then `filter.tags.add(tag)` (checked: it throws, also for a
  `Filter()` built without `const`). `final` only stops reassignment; a `final` list can still
  change. Copy a collection the code did not create before changing it: `[...tags, tag]`.
- **Copying.** `List.of(xs)`, `[...xs]` and `xs.toList()` keep the element type. `List.from(xs)`
  takes an `Iterable<dynamic>`: without a type argument it returns a `List<dynamic>`, and
  `List<int>.from(objects)` casts each element at run time and throws a `TypeError` at the first
  one of another type (checked). Filter by type with `whereType<T>()`; `cast<T>()` gives a view.
- **Loops.** `for (final x in xs)`. `forEach` does not wait for an `async` function literal
  (checked: the code after `forEach` ran before either callback finished), and `break` or `return`
  cannot leave it (`return` ends one callback). The template's lints agree:
  `avoid_function_literals_in_foreach_calls` reports a literal, and `prefer_foreach` asks for
  `xs.forEach(f)` when a `for` loop only calls a tear-off, the one place for `forEach`.
- **Deep data.** Dart has no tail-call elimination. Recursion over data whose depth the program
  does not control (a JSON tree from the server, a folder tree) can end in a `StackOverflowError`
  (checked: a trivial recursive function overflowed at about 20,000 calls on the main isolate).
  Walk such data with a loop and an explicit stack (a `List` or a `Queue`).

## Strings and text length

A `String` is a sequence of UTF-16 code units. `length`, indexes and `substring` count those, not
what the user sees as one character (checked):

| Text | `length` | `runes.length` | UTF-8 bytes | `characters.length` |
| --- | --- | --- | --- | --- |
| `'😀'` | 2 | 1 | 4 | 1 |
| `'👨‍👩‍👧'` (three emoji joined) | 8 | 5 | 18 | 1 |

- Anything the user sees or counts (a length limit, a counter, a shortened name or preview, the
  first letter for an avatar) uses grapheme clusters through `characters`, which
  `package:flutter/widgets.dart` re-exports: `text.characters.length`,
  `text.characters.take(n).toString()`, `text.characters.first` on a non-empty text.
  `TextField(maxLength:)` and `LengthLimitingTextInputFormatter` already count this way.
- `length` and `substring` are for text the program controls: ids, ASCII codes, protocol fields.
  Cut by code units, text can end in half a surrogate pair: `'Hi😀'.substring(0, 3)` does, and
  `utf8.encode` turns the half into U+FFFD, so the data changes without an error (checked).
- Bytes from outside are decoded as UTF-8 explicitly: see "Decoding response bodies" in
  `docs/rules/repositories.md`.

## Null checks without `!`

A private final field is promoted after a null check (Dart 3.2): `_value != null ? _value + 1 :
0` compiles. A public field or a getter is not ("refers to a public property so it couldn't be
promoted"; checked), because another library could override it with a getter that answers
differently on the second read. Do not add `!` to silence that:

```dart
if (widget.user case final user?) greet(user); // binds the non-null value
final next = switch (state.count) { final count? => count + 1, null => 0 };
final user = widget.user; // a local is promoted
if (user != null) greet(user);
```

`!` is for a value that cannot be null because of an invariant the code itself keeps, not for one
that "was checked above".

## Records

- A record is for a few values one function returns together: `(List<Product>, int total)` for a
  page. Name the fields when there are more than two, or when the types do not say what they mean.
  A record type used in more than one signature gets a `typedef` with a doc comment
  (`typedef TokenPair = ({String access, String refresh});`).
- Use a `final class` when the value has behaviour, needs a doc per field, crosses JSON or the
  database, or travels through several layers.
- `==` compares the fields with their own `==`, named fields in any order:
  `(a: 1, b: 2) == (b: 2, a: 1)` is true. A `List` or `Map` field compares by identity:
  `([1], 1) == ([1], 1)` is false (checked). So a selector record holding a list (see "Rebuilding
  on one part of a notifier" in `docs/rules/widgets.md`) notifies for every new list, even an
  equal one, and never for a list changed in place: select its length or a value.
- Swap two variables with `(a, b) = (b, a);`.

## Platform-specific code

When the web and the native platforms need different code (files, processes, a JS API), give each
its own file and let a conditional export pick one at compile time:

```dart
// device_name.dart: what the rest of the app imports
export 'device_name_stub.dart'
    if (dart.library.js_interop) 'device_name_js.dart'
    if (dart.library.io) 'device_name_vm.dart';
```

```dart
// device_name_stub.dart: the same API, for a platform with neither library
String deviceName() => throw UnsupportedError('No implementation for this platform');

// device_name_js.dart
String deviceName() => 'web';

// device_name_vm.dart: the only file that imports dart:io
import 'dart:io' as io;

String deviceName() => switch (io.Platform.operatingSystem) {
  'android' => 'Android',
  'ios' => 'iOS',
  final other => other,
};
```

- Every file exposes the same declarations; the compiler checks each against its callers only on
  its own platform, so keep them in step by hand.
- With two targets, the stub can go: `export 'device_name_vm.dart' if (dart.library.js_interop)
  'device_name_js.dart';`.
- Test for `dart.library.js_interop` (the web, with both compilers), not the old
  `dart.library.html`.
- Inside the `dart:io` file, branch with `io.Platform.isAndroid`, `isIOS`, `isMacOS`, ...; the
  rest of the app never imports `dart:io` for that.
- UI decisions (which widget, which gesture) use `defaultTargetPlatform` instead, which a test can
  override with `debugDefaultTargetPlatformOverride` and which works on the web.

## Patterns

A pattern checks that a value has a shape and binds the parts it names. They work in `switch`
statements and expressions, in `if-case`, in `for` loops and in variable declarations and
assignments.

| Pattern | Example | Matches |
| --- | --- | --- |
| Constant | `'ok'`, `404`, `null` | an equal value |
| Variable | `final int id`, `var name` | anything (of that type), binding it |
| Wildcard | `_`, `int _` | anything, binding nothing |
| Relational | `== 0`, `< 10`, `>= 200` | a comparison that holds |
| Logical-or / -and | `'a' \|\| 'b'`, `> 0 && < 10` | either / both subpatterns |
| Null-check | `final String name?` | a non-null value, typed non-null |
| Null-assert | `final name!` | a non-null value, throwing on `null` |
| Cast | `final int id as num` | anything, cast (throws when it is not) |
| Record | `(final x, _, final z)`, `(:name, :age)` | a record of that shape |
| Object | `Product(:id, price: > 0)` | an instance with those getters |
| List | `[final first, ...]`, `[_, _]` | a list of that length, with a rest |
| Map | `{'id': final int id}` | a map with those keys (others allowed) |

`!` in a pattern is the null-assert pattern above, not a logical "not"; there is no negation
pattern (use `!=` or a `when` guard).

### Where they help

- **States.** A widget switches over a controller's sealed state, and the compiler checks that
  every state is handled:

```dart
builder: (context, state, child) => switch (state) {
  Products$ProcessingState(:final products) when products.isEmpty => const Spinner(),
  Products$IdleState(:final products) || Products$SuccessfulState(:final products)
      when products.isEmpty => const EmptyView(),
  Products$IdleState() ||
  Products$ProcessingState() ||
  Products$SuccessfulState() ||
  Products$ErrorState() => ProductsList(products: state.products),
},
```

  (An error is shown by the `listener`, not here: see `docs/rules/controllers.md`.)

- **JSON in converters.** A map pattern checks the keys and types at once and binds them; a
  response that does not match falls through to a clear error instead of a cast error deep inside:

```dart
Product convert(Map<String, Object?> json) => switch (json) {
  {'id': final int id, 'name': final String name, 'price': final num price} =>
    Product(id: id, name: name, price: price.toDouble()),
  _ => throw FormatException('Not a product', json),
};
```

  Required fields go in the pattern; an optional one is read beside it with a default
  (`isPrimary: json['is_primary'] == true`); a date is parsed after the match, inside the same
  error handling (`DateTime.parse` throws `FormatException` on a bad string). A response that does
  not match is bad input, so throw `FormatException` (with the data), not `ArgumentError`, which
  means the calling code is wrong.

- **Destructuring.** Records and map entries come apart where they are declared:

```dart
final (:name, :age) = person;
final (products, total) = await _repository.products(page: 1);
for (final MapEntry(:key, :value) in counts.entries) {
  print('$key: $value');
}
```

- **Guards.** `when` adds a condition to a case: `Products$IdleState(:final products) when
  products.isEmpty => const EmptyView()`.

### Rules

- Without a `sealed` (or enum) type a `switch` needs a `_` arm; with one, leave it out, so adding a
  variant breaks the build where it must be handled.
- Prefer `switch` expressions (`=> ... ,`) for values and `switch` statements for side effects; a
  statement's cases do not fall through, so no `break` is needed after a non-empty case.
- In a widget tree, a closure called on the spot (`child: () { switch (value) { ... } }()`) is the
  pre-Dart 3 way to choose a widget: write a `switch` expression (`child: switch (value) { 1 =>
  const Text('One'), _ => const Text('Other') }`), an `if`/`else` collection element, or a small
  widget class. The closure is rebuilt on every build and hides an unnamed branch.
- A cast pattern (`as`) and the null-assert pattern (`!`) throw when they do not match: use them
  only where a mismatch is a bug, and the checking patterns (`final int id`, `?`) where it is input.
- A record pattern matches only a record of exactly its shape: the same number of positional
  fields and the same names, with no `...` rest as in a list pattern. `(String _, int age)` never
  matches a record with three fields, so the `switch` always takes another arm, and the analyzer
  only warns `pattern_never_matches_value_type` (checked): treat that warning as an error.
- A `sealed` family is for a closed set of variants that many places handle (states, events, JSON
  variants): a new variant is a compile error at every `switch`. An `is` chain over an open type
  lets a new subtype compile and fall into the default branch (checked: no diagnostic). For an open
  set that features add to (commands, handlers by name), put the behaviour on the type (a method
  of the interface) or in a map from key to handler, so adding one changes no existing code.

### Examples

#### `patterns.dart`

```dart
// file: patterns.dart
import 'dart:convert';

/// A response body in one of three shapes; `sealed`, so a switch over it is exhaustive.
sealed class ResponseBody {
  const ResponseBody();
}

final class StringResponseBody extends ResponseBody {
  const StringResponseBody(this.body);

  final String body;
}

final class BytesResponseBody extends ResponseBody {
  const BytesResponseBody(this.body);

  final List<int> body;
}

final class MapResponseBody extends ResponseBody {
  const MapResponseBody(this.body);

  final Map<String, Object?> body;
}

/// The body as JSON; no `_` arm, so a new body type fails to compile here until it is handled.
Map<String, Object?> decode(ResponseBody data) => switch (data) {
  StringResponseBody(:final body) => _object(jsonDecode(body)),
  BytesResponseBody(:final body) => _object(_utf8Json.convert(body)),
  MapResponseBody(:final body) => body,
};

/// UTF-8 bytes to JSON in one pass, without an intermediate `String`.
final Converter<List<int>, Object?> _utf8Json = utf8.decoder.fuse(json.decoder);

Map<String, Object?> _object(Object? json) => switch (json) {
  final Map<String, Object?> map => map,
  _ => throw FormatException('Not a JSON object', json),
};

/// A product, read with a map pattern: the keys and their types are checked at once.
final class Product {
  const Product({required this.id, required this.name, required this.price});

  final int id;
  final String name;
  final double price;
}

/// Converts a product's JSON; anything else is a [FormatException] that names it.
Product productFromJson(Map<String, Object?> json) => switch (json) {
  {'id': final int id, 'name': final String name, 'price': final num price} => Product(
    id: id,
    name: name,
    price: price.toDouble(),
  ),
  _ => throw FormatException('Not a product', json),
};

/// A status code in words, with relational and logical-or patterns.
String describe(int statusCode) => switch (statusCode) {
  >= 200 && < 300 => 'success',
  401 || 403 => 'not allowed',
  >= 400 && < 500 => 'client error',
  >= 500 => 'server error',
  _ => 'unexpected',
};

/// Destructuring a record, with a wildcard for the part that is not needed.
String summary(({String name, int age}) person, (int, int, int) point) {
  final (:name, :age) = person;
  final (x, _, z) = point;
  return '$name is $age years old; x = $x, z = $z';
}
```

#### `profile_screen_data.dart`

```dart
// file: profile_screen_data.dart
import 'dart:async';

/// A user's profile.
final class Profile {
  /// Creates a profile.
  const Profile(this.name);

  /// The display name.
  final String name;
}

/// The data of the profile screen.
abstract interface class IProfileRepository {
  /// The profile.
  Future<Profile> profile();

  /// The number of unread messages.
  Future<int> unreadCount();
}

/// Loads both values at once, typed; a failure of either is rethrown as itself.
Future<(Profile, int)> loadProfileScreen(IProfileRepository repository) async {
  try {
    return await (repository.profile(), repository.unreadCount()).wait;
    // ignore: avoid_catching_errors, ParallelWaitError only wraps the real failures.
  } on ParallelWaitError<(Profile?, int?), (AsyncError?, AsyncError?)> catch (error) {
    // Every failure is here, each with its own stack trace; rethrow the first as itself.
    final first = error.errors.$1 ?? error.errors.$2!;
    Error.throwWithStackTrace(first.error, first.stackTrace);
  }
}
```

#### `value_types.dart`

```dart
// file: value_types.dart
/// A calendar date without a time of day: a birthday, a due date.
///
/// Every constructor drops the time, so two dates of the same day are equal.
extension type const Date._(DateTime _date) implements Object {
  Date(int year, int month, int day) : _date = DateTime.utc(year, month, day);

  /// The local date of [moment].
  Date.of(DateTime moment) : this(moment.year, moment.month, moment.day);

  /// Parses `YYYY-MM-DD`.
  static Date? tryParse(String text) => switch (DateTime.tryParse(text)) {
    final DateTime date when text.length == 10 => Date.of(date),
    _ => null,
  };

  int get year => _date.year;
  int get month => _date.month;
  int get day => _date.day;

  /// `YYYY-MM-DD`, the form to store and send.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Days from [other] to this date.
  int differenceInDays(Date other) => _date.difference(other._date).inDays;

  bool isBefore(Date other) => _date.isBefore(other._date);
}

/// Issues of a new password, as bits of one `int`: no list, no allocation.
extension type const PasswordIssues(int _bits) {
  static const PasswordIssues none = PasswordIssues(0);
  static const PasswordIssues tooShort = PasswordIssues(1 << 0);
  static const PasswordIssues mismatch = PasswordIssues(1 << 1);

  bool contains(PasswordIssues issue) => _bits & issue._bits != 0;

  PasswordIssues operator |(PasswordIssues other) => PasswordIssues(_bits | other._bits);

  bool get isEmpty => _bits == 0;
}
```

#### `lazy_future.dart`

```dart
// file: lazy_future.dart
import 'dart:async';

/// Runs [_create] on first use and shares the one result with every caller, concurrent or later.
///
/// Unlike `late final Future<T> x = create();` a failure is not kept: the next call tries again.
final class LazyFuture<T> {
  LazyFuture(this._create);

  final Future<T> Function() _create;
  Future<T>? _future;

  /// The value; starts [_create] when no attempt is running or has succeeded.
  Future<T> get value =>
      _future ??= _create().onError<Object>((error, stackTrace) {
        _future = null; // forget the failure, so the next call creates again
        Error.throwWithStackTrace(error, stackTrace);
      });
}
```
