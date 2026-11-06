---
name: architecture
description: "Project layout and layers, and the shape of list, creation, deletion and by-id features, with example files."
---

# Architecture

## Rules

- `lib/main.dart` is the entry; everything else is in `lib/src/`: `_core/` for code shared by
  features, and one folder per feature directly in `lib/src/` (`lib/src/authentication/`), with no
  `feature/` folder around them. A project that already has another layout (`common/`,
  `feature/`) keeps it. See "Project structure".
- A feature has `models/`, `data/` (repository), `controller/`, `widgets/`. Name files
  `<feature>_<role>.dart`.
- Dependencies point one way: widgets -> controller -> repository. A widget never touches a
  repository.
- Data providers only when needed: a repository with one simple source queries it and converts
  the result itself; a feature with two sources (a local cache and a server) or a heavy one
  (GraphQL, SQL, protobuf) puts each behind a data provider interface. See "Data providers".
- A feature is a screen (or a few closely related screens) and what belongs to it; a model used by
  several features lives in the feature that owns it. See "What a feature is".
- No use cases, interactors or "services" between a controller and its repositories: a controller
  that needs two repositories takes both. A repository never depends on another repository. See
  "No use cases or services".
- Generated classes (drift rows, GraphQL, OpenAPI, protobuf) never cross a repository's interface:
  the repository returns the feature's own models. See "Models at the data boundary".
- Class members in Dart's order: constructors and factories, static members, fields and getters,
  methods. See "Member order".
- A detail screen loaded by id, a create/update form and a delete action are each their own
  feature (`x_detail`, `x_creation`, `x_deletion`).
- Models are immutable. Parse API JSON in a converter, not in widgets.
- Every constructor parameter of a model is `required`, nullable ones too
  (`required this.description` for a `String?`). Models are built from JSON and database rows in
  a few places; when a field is added later, the compiler then points at every place that must
  fill it, instead of the field silently staying `null`.
- A control used by two or more features goes to `lib/src/_core/widget/`.
- No Provider, Riverpod, MobX, GetX or BLoC for widget state.
- Law of Demeter: talk to your direct collaborators, not to their insides (`car.start()`, not
  `car.engine.start()`). See "Law of Demeter".
- Single source of truth: every piece of data has one owner (a database, a repository, an app-wide
  controller such as authentication); everything else reads from it instead of keeping a copy.
- Side effects (network, disk, database, timers, global state) happen in repositories and are
  started by controllers; models, converters, state getters and `build` methods are pure. See "Side
  effects".
- Keep the user, the user's info and the sessions as separate models; never one `User` with
  everything. See "Users, user info and sessions".
- Code that others call (a shared package, `_core/`, an API other teams use) is changed by
  adding: mark the old member `@Deprecated('Use x instead')` instead of removing or reshaping it,
  and remove it a couple of releases later. To keep CI green meanwhile, ignore only
  `deprecated_member_use_from_same_package`, never `deprecated_member_use`. See "Changing shared
  code".
- A model has the fields the app reads, not every field of the payload. See "Models at the data
  boundary".
- When a screen shows the cached data and then the fresh, the repository has two methods and the
  controller picks the order. See "Cache and network as two methods".

## Feature architecture

### Project structure

```
lib/
├── main.dart
└── src/
    ├── _core/            # shared by features: utilities, widgets, database, config, localization
    ├── initialization/   # startup and the app's dependencies
    ├── authentication/   # one folder per feature, directly in src/
    └── home/
test/                     # mirrors lib/src/: test/_core/, test/authentication/, ...
```

- `lib/main.dart`, `lib/src/` and `lib/src/_core/` always exist; every other folder in `lib/src/`
  is a feature. Nothing but `main.dart` sits directly under `lib/`.
- `_core` holds only what belongs to no single feature. The underscore sorts it before the
  features in every file list, and a feature is never named `_core`.
- A `feature/` folder around the features adds a level to every import and to every path in the
  tree without saying anything a top-level folder does not.
- If the project already has its folders (`lib/src/common/` and `lib/src/feature/`, or any other
  layout), keep them: do not move existing code to match these rules. Create only what is
  missing, in the layout the project uses.
- Use `example` as a placeholder for the real feature name. Do not invent another architecture
  unless the surrounding code already requires it.

### Layers and dependency direction

1. **UI**: `example_config_widget.dart` creates and owns the controllers.
2. **UI state**: `example_data_controller.dart` (a `ChangeNotifier`) holds filters, search, selection.
3. **Business logic**: `example_controller.dart` runs async work and holds `StateController` state.
4. **Data**: `example_repository.dart` talks to the API, database, files.
5. **Models**: `example.dart` is the domain entity.

The whole chain is `Widget <-> Controller <- Repository <- client or database`: widgets call the
controller and listen to it, the controller calls repositories, a repository calls its clients.
There is no presenter (the widgets adapt the state themselves) and no interactor or use case
between a controller and its repositories (see "No use cases or services").

The dependency direction is strictly `widgets -> controller -> data (repository)`. Widgets, widget
states, config-widget states and data controllers never hold a repository. If a widget needs data
(quick replies, workers, settings), the controller fetches it and exposes it in the state.

```dart
// Wrong: a widget calling a repository.
deps.someRepository.loadData();

// Right: the widget asks the controller.
late final _controller = MyConfigInhWidget.of(context).myController;
@override
void initState() {
  super.initState();
  _controller.load();
}
```

### List / screen feature

A feature that loads and shows a list, dashboard, detail screen or infinite-scroll table:

```
example/
├── controller/
│   ├── example_controller.dart
│   └── example_controller.freezed.dart      (generated)
├── data/
│   └── example_repository.dart
├── models/
│   ├── example.dart
│   ├── example_json_converter.dart
│   └── example_permissions.dart             # only when the project has feature permissions
└── widgets/
    ├── controllers/
    │   └── example_data_controller.dart     # filters/search/local UI state, only when needed
    ├── desktop/example_desktop_widget.dart  # only when the project has a desktop UI
    ├── mobile/example_mobile_widget.dart    # only when the project has a mobile UI
    └── example_config_widget.dart
```

- `example_config_widget.dart` creates controllers in `initState`, disposes them in `dispose` and
  exposes them through `ExampleConfigInhWidget extends InheritedWidget`.
- `ExampleConfigWidgetState` owns `load()` and `paginate()` when the feature loads and scrolls.
- If the project has authentication, load data after sign-in (the project's authentication
  listener) when identity or permissions are needed, and check permissions before loading data and
  before showing create/update/delete/action buttons.
- Where the project has separate desktop and mobile UIs, they live in `widgets/desktop/` and
  `widgets/mobile/`, picked with
  `context.screenSizeMaybeWhen(orElse: () => const ExampleMobileWidget(), desktop: () => const ExampleDesktopWidget())`.
  Add tablet only for a dedicated tablet UI. A single-platform project uses plain widgets.

Templates: `example.dart`, `example_json_converter.dart`, `example_repository.dart`,
`example_controller.dart`, `example_data_controller.dart`, `example_config_widget.dart`,
`example_widget.dart` (in Examples below; adjust the imports to the feature layout).

#### Config widget navigation

A navigable feature has a typed page (`ExamplePage`) whose child is its config widget, and opens with
`AppNavigator.push`. A static `open()` on the config widget keeps the call to one line:

```dart
static void open(BuildContext context, {Example? example, DesktopController? desktopController}) =>
    context.screenSizeMaybeWhen(
      orElse: () => AppNavigator.push(context, ExamplePage(example: example)),
      desktop: () =>
          desktopController?.setModule(exampleModule(example: example), clearModules: false),
    );
```

- Screens open through the declarative navigator (`docs/rules/navigation.md`), never with
  `Navigator.push(MaterialPageRoute(...))`. Dialogs and sheets stay `showDialog` /
  `Navigator.pop`.
- Desktop navigation, when the project has a desktop shell, goes through
  `DesktopController.setModule(...)` and module factories. Module factories belong in the project's
  home-module file (for example `lib/src/home/models/home_module_permission.dart`).
- Pass parameters through config widgets and module factories; no globals.
- `clearModules: false` for child/detail/create screens opened from another desktop module. If a
  module is opened to pick an object, capture `currentModule` and return with
  `desktopController.breadCrumbModule(currentModule)`.

### Creation / update feature

Forms are separate features because their save state is independent of the list:

```
example_creation/
├── controller/example_creation_controller.dart
├── data/example_creation_repository.dart
└── widgets/
    ├── controllers/example_creation_data_controller.dart
    ├── desktop/ ... / mobile/ ...                       (as the project needs)
    └── example_creation_config_widget.dart
```

- Form state lives in `example_creation_data_controller.dart`, a `ChangeNotifier` holding an
  immutable draft until save. Widgets read and write only through it, then call `scope.save()`.
- The async controller uses `DroppableControllerHandler`.
- Create and update can share a controller and repository interface. If POST and PATCH differ,
  make `ExampleCreationRepositoryImpl` and `ExampleUpdateRepositoryImpl` in the same file.
- If the form can open as a dialog, add an `openDialog()` factory and wrap the dialog body in
  `ScaffoldMessenger` so snackbars work.

### Deletion feature

```
example_deletion/
├── controller/example_deletion_controller.dart
├── data/example_deletion_repository.dart
└── widgets/
    ├── example_deletion_config_widget.dart
    └── example_deletion_dialog_widget.dart
```

- `DroppableControllerHandler`. The config widget exposes a static `show(...)`.
- The dialog uses `StateConsumer` and closes itself on `SuccessfulState`. Call the success callback
  before closing so the parent can reload.
- Use the project's confirmation dialog (for example `AdaptiveDialogWidget`) or the established
  local style.

Config widget:

```dart
class ExampleDeletionConfigWidget extends StatefulWidget {
  const ExampleDeletionConfigWidget({
    super.key,
    required this.exampleId,
    required this.builder,
    this.onSuccessfullyDelete,
  });

  static Future<void> show(BuildContext context, {required int exampleId, VoidCallback? onSuccessfullyDelete}) =>
      showDialog(
        context: context,
        builder: (context) => ExampleDeletionConfigWidget(
          exampleId: exampleId,
          onSuccessfullyDelete: onSuccessfullyDelete,
          builder: (context) => const ExampleDeletionDialogWidget(),
        ),
      );

  final int exampleId;
  final WidgetBuilder builder;
  final VoidCallback? onSuccessfullyDelete;

  @override
  State<ExampleDeletionConfigWidget> createState() => ExampleDeletionConfigWidgetState();
}

class ExampleDeletionConfigWidgetState extends State<ExampleDeletionConfigWidget> {
  late final ExampleDeletionController exampleDeletionController;
  late final exampleId = widget.exampleId;
  late final onSuccessfullyDelete = widget.onSuccessfullyDelete;

  @override
  void initState() {
    super.initState();
    final dependencies = DependenciesScope.of(context);
    exampleDeletionController = ExampleDeletionController(
      exampleDeletionRepository: ExampleDeletionRepositoryImpl(apiClient: dependencies.apiClient),
    );
  }

  @override
  void dispose() {
    exampleDeletionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ExampleDeletionConfigInhWidget(state: this, child: widget.builder(context));
}
```

Dialog widget:

```dart
StateConsumer<ExampleDeletionController, ExampleDeletionState>(
  controller: _controller,
  listener: (context, controller, oldState, newState) {
    if (newState is ExampleDeletion$SuccessfulState) {
      _scope.onSuccessfullyDelete?.call();
      Navigator.pop(context);
    }
  },
  builder: (context, state, child) => AdaptiveDialogWidget(
    title: Localization.of(context).exampleDeletion,
    content: Localization.of(context).exampleDeletionConfirm,
    inProgress: state is ExampleDeletion$ProcessingState,
    onConfirm: (_) => _controller.delete(
      _scope.exampleId,
      onMessage: (message) => showMessage(context, message: message),
    ),
  ),
)
```

Runnable pieces: `docs/rules/controllers.md` (`example_deletion_controller.dart`,
`example_deletion_dialog.dart`).

### By-id loader feature

For a caller that has only an id while the destination needs the full model:

```
example_by_id/
├── controller/example_by_id_controller.dart
├── data/
│   ├── example_by_id_repository.dart
│   └── example_json_converter.dart      # if the response needs its own converter
└── widgets/
    ├── example_by_id_config_widget.dart
    └── example_by_id_edit_loader_widget.dart
```

- A detail screen loaded by id is its own feature, separate from the list that links to it (for
  example `receipts` -> `receipt_detail`): independent controller, load state and repository.
- The config widget receives the id, creates the by-id controller and calls `load(id)` at once.
- The loader widget listens for `SuccessfulState`, closes the loading dialog, then opens the
  destination view/edit screen (mobile `AppNavigator.push`, desktop `desktopController.setModule`).
- On `ErrorState` the listener shows the error with a retry (`() => controller.load(id)`); the
  state goes back to `idle` right after, so the builder never shows the error itself.

### Single source of truth

Every piece of data lives in one place, its owner, and every part of the app reads it from there.
Copies go stale: two widgets holding their own copy of a list disagree after the first change, and
nobody knows which one is right.

- The owner is where the real data is kept: the server or local database behind a repository, or
  an app-wide controller for app state (authentication, the selected store).
- A screen's controller holds what the screen shows, read from the owner; it is a view of the data,
  not a second owner. A list watches the repository's stream (or reloads) instead of patching its
  own copy after another feature changed the data. That stream comes from the store (a database
  `watch()`), not from a `StreamController` kept in the repository: see "No state in a repository"
  in `docs/rules/repositories.md`.
- A change goes to the owner first (the repository writes it), and everyone who shows the data
  learns about it from the owner: the stream emits, or the list reloads.
- App-global values (the selected store, the active organisation) are read from their owner by the
  repository on each call, not copied into every controller and widget.

### Models and JSON converters

```
models/
├── example.dart
├── example_json_converter.dart
└── example_permissions.dart             # only when needed
```

- Models are `@immutable` with final fields (or freezed). `copyWith` takes `ValueGetter<T?>?` for
  nullable fields so a value can be explicitly cleared (`description: () => null`).
- No `equatable`: let freezed generate `==` and `hashCode`, or override them yourself
  (`other is Example && other.id == id && ...`, `Object.hash(id, name)`).
- API parsing is a `Converter<Map<String, Object?>, Example>`. Keep snake_case API keys in
  converters and repositories, not in widgets.
- Parse backend numbers tolerantly: `double.tryParse('${json['amount']}')`,
  `int.tryParse('${json['id']}')`.
- No private `_exampleFromJson` helpers in widgets or repositories when the parsing belongs in
  `models/example_json_converter.dart`.

### Models at the data boundary

A repository's interface speaks only the feature's own models (`Category`, `Product`). What the
transport or the database generates stays inside the repository's implementation and is converted
right there:

```dart
final class CategoriesRepositoryImpl implements ICategoriesRepository {
  CategoriesRepositoryImpl({required this._database});

  final AppDatabase _database;

  @override
  Future<List<Category>> categories({int page = 1, int itemsPerPage = 20}) async {
    final rows = await (_database.select(_database.categoriesTable)
          ..limit(itemsPerPage, offset: (page - 1) * itemsPerPage))
        .get();
    // The drift row type never leaves this method.
    return rows.map(const CategoryFromTableConverter().convert).toList();
  }
}
```

- Drift's generated row classes, GraphQL / OpenAPI / protobuf classes and raw JSON maps are
  converted to models inside the repository's implementation, or inside the data provider's when
  there is one, by a converter in `models/` (`category_from_table_converter.dart`,
  `example_json_converter.dart`) and never appear in a repository's interface, a controller or a
  widget.
- The reason: the transport changes (REST to GraphQL to protobuf, or the backend reshapes its
  responses). When only the converter knows the wire format, a change stays in one file instead of
  spreading through the app.
- No hand-written "remote" and "local" model pairs, where the repository copies one into the other:
  one model per concept, and the converter maps the wire or table format to it.
- The model has the fields the app reads, and no others. The converter picks them out and ignores
  the rest of the payload (a book's editions, reviews and the author's birth date, when the screen
  shows a title and a cover): a field the backend adds, renames or drops then touches nothing, and
  the model says what the feature uses. A field is added to the model when a screen needs it.
- When one model needs data from two sources (a user and their address), the repository awaits
  both and builds the model in a private method; no new class between them.

### Data providers

The data layer has up to three levels:

- **Client** (a database, an HTTP client, an executor): a small API that runs a request
  (`Future<Response> execute(Request request)`) or a query. Created once at startup and shared.
- **Data provider** (a data access object, an adapter): uses one client, which it gets through its
  constructor, and returns the feature's models, decoding the response inside itself.
- **Repository** (a facade): uses one or more data providers and is what the controller talks to.

A repository with a single, simple source (one drift table, one REST endpoint) queries it and
converts the result itself, as `CategoriesRepositoryImpl` above. When the feature has two sources
(a local cache and a server) or a heavy one (GraphQL, SQL, protobuf), each source gets a data
provider: an interface in the feature's `data/` folder and an implementation named after its
technology. The repository works with the interfaces only:

```dart
FeatureController(
  repository: FeatureRepositoryImpl(
    local: FeatureLocalDataProvider$SQLiteImpl(database: database),
    remote: FeatureRemoteDataProvider$GraphQLImpl(client: graphQLClient),
  ),
);
```

```dart
abstract interface class IFeatureLocalDataProvider {
  Future<Item?> itemById(String id);
}

final class FeatureLocalDataProvider$SQLiteImpl implements IFeatureLocalDataProvider {
  FeatureLocalDataProvider$SQLiteImpl({required this._database});

  final AppDatabase _database;

  @override
  Future<Item?> itemById(String id) async {
    final row = await (_database.select(_database.items)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    // The drift row ends here: the interface returns the feature's own model.
    return row == null ? null : Item(id: row.id, name: row.name);
  }
}
```

```
lib/src/authentication/
├── models/      user.dart
├── data/        auth_repository.dart
│                auth_local_data_provider.dart
│                auth_remote_data_provider.dart
├── controller/  auth_controller.dart
└── widgets/     auth_screen.dart, auth_form.dart
```

- No type of an implementation appears in a data provider's interface: no drift rows, GraphQL or
  protobuf classes, no `Database` or client types. Everything generated ends inside the provider's
  implementation; the repository does not even import it.
- Every method of a repository and of a data provider is asynchronous (`Future` or `Stream`), even
  when today's implementation is synchronous: the next implementation (a network call, an isolate)
  then changes nothing above it.
- No DTOs between a provider and its repository: the provider already returns the feature's model.
  A `Map<String, Object?>` of plain values is an acceptable shortcut for an argument or a result,
  never one holding generated types.
- The repository decides what comes from where (the cache when the server fails, write through to
  both); the providers know nothing of each other. When the screen shows both (the stored copy
  now, the fresh one when it comes), see "Cache and network as two methods".

### Several services behind one interface

When the app sends the same calls to several services (analytics to PostHog and Google Analytics,
logs to the console and Sentry), callers depend on one interface. One implementation per service,
and one more that forwards every call to a list of them. Adding or dropping a service changes the
list built at startup (an initialization step), not the callers.

The merged implementation catches each service's error itself. `Future.wait` waits for every
future and then throws the first error, so one failing service would otherwise fail the caller's
action. Analytics never breaks what the user is doing.

```dart
// file: analytics_reporter.dart
import 'package:flutter/foundation.dart';

/// An analytics event: a name and its parameters.
@immutable
final class AnalyticsEvent {
  const AnalyticsEvent(this.name, [this.parameters = const <String, Object>{}]);

  final String name;
  final Map<String, Object> parameters;
}

/// Sends analytics to one service.
abstract interface class IAnalyticsReporter {
  Future<void> logEvent(AnalyticsEvent event);

  Future<void> setUserId(String? userId);
}

/// Sends every call to all reporters; an error in one is reported and does not stop the others.
final class MergedAnalyticsReporter implements IAnalyticsReporter {
  const MergedAnalyticsReporter(this._reporters, {required this._onError});

  final List<IAnalyticsReporter> _reporters;
  final void Function(Object error, StackTrace stackTrace) _onError;

  @override
  Future<void> logEvent(AnalyticsEvent event) => _forEach((reporter) => reporter.logEvent(event));

  @override
  Future<void> setUserId(String? userId) => _forEach((reporter) => reporter.setUserId(userId));

  Future<void> _forEach(Future<void> Function(IAnalyticsReporter reporter) call) => Future.wait(
    _reporters.map((reporter) async {
      try {
        await call(reporter);
      } on Object catch (error, stackTrace) {
        _onError(error, stackTrace);
      }
    }),
  );
}
```

### What the repository does

A repository juggles its sources and their results: look in the cache, ask the server when the
cache has nothing, save the answer to the cache. Where a method has only one source, it simply
passes the call on, and that is fine:

```dart
final class ProductsSyncRepositoryImpl implements IProductsSyncRepository {
  ProductsSyncRepositoryImpl({
    required this._remote,
    required this._local,
    required this._preferences,
  });

  final IProductsSyncRemoteDataProvider _remote;
  final IProductsLocalDataProvider _local;
  final SharedPreferences _preferences;

  /// Fetches what changed, saves it, and only then moves the sync mark: a failed save leaves the
  /// mark where it was, so the next sync fetches the same products again instead of losing them.
  @override
  Future<List<Product>> sync() async {
    final since = _preferences.getString('products_synced_at');
    final products = await _remote.productsChangedSince(since);
    final deleted = await _remote.deletedSince(since);
    final saved = await _local.save(products);
    final removed = await _local.delete(deleted);
    if (saved && removed) {
      await _preferences.setString('products_synced_at', clock.now().toIso8601String());
    }
    return products;
  }

  /// One source: the call is passed on.
  @override
  Future<void> clear() => _local.clear();
}
```

- The data providers already return the feature's models, so the repository does not convert
  anything; it decides the order and the policy (cache first, write through, what a failure
  leaves behind).
- A repository whose methods all just pass calls to one provider is a sign the provider is not
  needed: query the source in the repository (see "Data providers").
- Some projects call data providers "data sources" (`IProductsLocalDatasource`); the role is the
  same.

### Cache and network as two methods

When the screen shows the stored data at once and the server's when it arrives, the repository
offers two methods instead of one that merges them: `cachedProducts()` reads the local copy,
`fetchProducts()` asks the server and saves the answer. The controller calls them in the order the
screen needs and decides what a failure of the second means (keep the cached rows, show the error):
see "Cached data first, then fresh" in `docs/rules/controllers.md`.

- One `Future` cannot return two answers, and a `Stream` that emits the cache and then the server
  hides from its caller which value is which, and what an error after the first value means.
- Each method stays a plain call that a test fakes in one line.
- A screen that needs only one answer (a background refresh, a by-id lookup) calls only one.

### What a feature is

A feature is one screen, or a few screens tightly related in meaning, and everything that belongs
to them; or a group of functionality tightly related in meaning with few imports from other
features. Usually: 1–2 screens, a few widgets, a set of models, 1–3 controllers, 1 repository and
1–2 data providers.

- A model, repository or piece of logic used by two features lives in the feature that is
  responsible for it, and the other feature imports it: the cart's models and logic live in the
  `cart` feature, whatever other screens show the cart. It moves to `_core/` only when it belongs
  to no feature (app-wide models in `_core/model/`, the database, the API client).
- One feature's repository never calls another feature's repository logic. When two features turn
  out to be one, merge them; until then, the controller that needs both takes both repository
  interfaces.
- Each feature asks its own repository for exactly what it shows (the first five items, the ones
  dated from tomorrow), instead of loading a full list and filtering it in the controller or the
  widget.

### Users, user info and sessions

Never merge these into one model, on the client or the server; combining them causes trouble in
the most unexpected places:

- **`User`**: immutable; who the user is: an id or email and what never or almost never changes. It
  does not hold the tokens: they live in the authentication session, out of what widgets rebuild on
  (see "Tokens" in `docs/rules/security.md`), so a refresh does not rebuild the screens.
- **`UserInfo`**: mutable and changes often: name, age, bio, avatar. Loaded and edited on its own.
- **`Session`**: one signed-in device: device, sign-in time, IP. Immutable for its lifetime; a user
  has a list of active sessions.
- **Roles and permissions** are their own model too.

A JWT combines a user and a session. Usually the client does not even need the user: the server
identifies it from the token that the auth middleware attaches to every request. A local database
seldom plans for several users on one device; decide that deliberately.

With Firebase Auth, Firebase is the owner of the user (see "Single source of truth"):

- Trust only its streams: `authStateChanges()` for signing in and out, `userChanges()` when the
  screen also shows profile fields (name, photo) that change without a new sign-in.
- Do not read `currentUser` to decide anything: the saved session is restored asynchronously after
  startup, so it is `null` at first and changes later on its own.
- Do not store the `User` yourself (preferences, a database, a field of another controller). An
  app-wide controller listens to the stream and publishes the user, and the widgets get it from an
  `InheritedWidget` above them.

### Repositories

`abstract interface class IExampleRepository` plus `ExampleRepositoryImpl` that receives its
services (API client, database, ...) through the constructor and does the request and the
conversion itself, or, when the feature has several sources, receives its data providers (see
"Data providers").

App-global scope values (selected store, active organisation) are read by the repository on each
call (it takes `SharedPreferences` or the scope service in its constructor). Only per-screen query
parameters (filters, search terms, ids) travel through `load(...)` / `paginate(...)`.

### No use cases or services

Use cases, interactors and "services" come from backend monoliths, where they connect sources that
must not know each other. On the client, between a controller and its repositories, they only add
classes that call each other: more code, more tests, nothing simpler.

- A controller that needs two repositories gets both through its constructor and calls them:
  `repo1.method(); repo2.method();`. Two controllers that react to each other do so through the
  widget that owns them (`addListener`), as in "Multiple controllers in one feature" of
  `docs/rules/controllers.md`.
- A repository never takes another repository in its constructor, and never uses another
  feature's repository or logic. When that seems needed, what is one feature was split in two: the
  controller takes both repository interfaces, and nothing sits between them.
- A piece of logic used by several methods of one repository is a private method of its
  implementation, not a new class.
- Transactions live in the database, not above it. Several calls from a controller (or a "service")
  are never atomic. Two writes that must succeed together are one repository method that runs one
  database transaction (`_database.transaction(() async { ... })`), or one backend endpoint. What is
  only being prepared (a cart before checkout) is plain state until that single write.
- A project that already has a use-case layer keeps it in the code that has it; new code does not
  mix the two styles in one feature.
- Whoever proposes a use-case layer shows the code: the same feature with and without it, with tests
  covering both equally. Without that, the layer is not added.

### Local database tables

Add a Drift table only for offline drafts or local persistence. See `docs/rules/repositories.md`.

### Localization

All visible widget text is localized: add every key to every `.arb` file
(`lib/src/_core/localization/intl_en.arb`, `intl_ru.arb`), use
`Localization.of(context).exampleKey`, reuse keys first, never hardcode text, never edit generated
localization files.

### Reusable widgets

A control used in more than one feature goes to `lib/src/_core/widget/`. Keep feature-specific UI in
its feature folder; promote only genuinely reused controls. Reuse existing common widgets for
tables, filters, reset/cancel buttons, status pills, empty/error/loading states, image viewers and
shimmer placeholders.

When the project has a design system (a `ui_library` package, `lib/src/_core/widget/` with design
tokens), build screens from its components and tokens. If a component is missing, ask before
adding it: a new shared component is a design decision, and styling it inline in a screen forks
the design.

### Widgets

- `StatefulWidget` for complex and root widgets and for anything that owns controllers, listeners,
  scroll state, text controllers, focus nodes or animations; `StatelessWidget` for small widgets
  (under 30-50 lines) that only render constructor values. When unsure for a parent: stateful.
- Keep `*_desktop_widget.dart` / `*_mobile_widget.dart` as screen composition files. Split cards,
  rows, filter bars and actions into files next to them. Do not use `part` / `part of` for splits.
- Business logic stays in controllers, scopes and data controllers; extracted widgets get values and
  callbacks through constructors.
- UI state in `widgets/` uses `ChangeNotifier` data controllers. Do not use Provider, Riverpod,
  MobX, GetX or BLoC for it.
- Observe a `ChangeNotifier` with `ListenableBuilder`. Use `const Foo({super.key})`.
- Read a feature scope with `late final _scope = ExampleConfigInhWidget.of(context);` and take
  controllers from it.

### Steps for a new feature

1. Create `lib/src/<feature>/{models,data,controller,widgets}` (only what is needed).
2. Model and converter, repository interface plus Impl, freezed states and controller.
3. Config widget (controllers in `initState`, disposed in `dispose`) and the screen widgets.
4. Register app-wide services in the dependency initialization (see `docs/rules/dependencies.md`).
5. Localize every visible string.
6. `dart run build_runner build --delete-conflicting-outputs && dart format lib/`
7. Unit-test the controller and repository with fakes.

## Changing shared code

Code that other people or other packages call (a shared package, `_core/`, an API that other teams
or apps use) changes by adding, not by removing:

- Do not delete a public class or method, and do not change what an existing method takes or does
  in a big way. Add the new one next to it, move the callers, and mark the old one:

```dart
@Deprecated('Use fetchProducts(page:) instead. Will be removed in 3.0.')
Future<List<Product>> loadProducts() => fetchProducts(page: 0);
```

- Remove it a couple of releases later, once nobody calls it. Branches written against the old
  name keep compiling meanwhile, and merges stay simple.
- The message names the replacement and when the old member goes ("Will be removed in 3.0", "when
  the new analytics is live"), so a caller knows what to do without asking.

### Deprecations, `flutter analyze` and CI

The analyzer reports every call of a deprecated member, under one of two names (checked with Dart
3.13 and `flutter_lints` 6):

- **`deprecated_member_use`**: the member comes from another package: the SDK, a pub package, or
  another package of the same repository (a path dependency). An info, on by default.
- **`deprecated_member_use_from_same_package`**: the member is declared in the same package (code
  in `lib/src/_core/` called from a feature). A lint, off in `flutter_lints`: it is reported only
  when `analysis_options.yaml` enables it under `linter: rules:`, and then as an info.

`flutter analyze` exits with 1 on any info (`dart analyze` only with `--fatal-infos`), so a
deprecation that is reported fails CI until every caller has moved, which defeats deprecating
instead of rewriting.

- When the project enables the same-package lint, let CI pass with callers still to move by
  setting `analyzer: errors: deprecated_member_use_from_same_package: ignore` (in CI or for the
  whole project). The `@Deprecated` message is still what tells the next developer to move.
- Never ignore `deprecated_member_use` in `analysis_options.yaml`: it also hides the deprecations
  of the SDK and the packages, the warning before an upgrade breaks the build. A caller in another
  package of the repository that cannot move yet gets `// ignore: deprecated_member_use` on that
  line, removed with the old member.
- Do not pass `--no-fatal-infos` to make the deprecations pass: every `flutter_lints` rule is an
  info, so it turns off the whole lint check.
- A new version lives next to the old one under a versioned name, and the old one says what
  replaces it: `getChatUpdatesV2` beside a `@Deprecated('Use getChatUpdatesV2 ...')`
  `getChatUpdates`, or `ChatRepository$HttpImpl$V2` beside `$V1` (an implementation is named after
  its technology, then its version).
- Private code of one feature, with every caller in the same change, is simply changed.

## Member order

Members of a class come in the order Dart code uses:

1. constructors and factory constructors;
2. static fields and static methods;
3. instance fields and getters (and setters);
4. methods (overrides such as `build` or `dispose` included), public before private.

```dart
final class ProductsController extends StateController<ProductsState> {
  ProductsController({required this._repository, super.initialState = const ProductsState.idle()});

  static const int pageSize = 50;

  final IProductsRepository _repository;

  bool get isEmpty => state.products.isEmpty;

  void load() => handle(() async { /* ... */ });

  void _reset() { /* ... */ }
}
```

## Side effects

A side effect is any change outside the function that runs: writing a field or a global, a network
request, reading or writing a file or the database, starting a timer, logging. A pure function has
none: its result depends only on its arguments, and calling it twice gives the same answer.

Side effects make code harder to test (the test has to set up and check the world around it),
cause surprising bugs (a global that something else changed), and cost time (a request or a write
on every call). They cannot be avoided, so they are kept in known places:

- **Repositories and data providers** do the I/O: requests, the database, files.
- **Controllers** start effects (they call the repository) and publish the result as state.
- **Everything else is pure**: models and their `copyWith`, converters, getters on a state,
  validation, formatting, calculations. Write these as plain functions or methods without
  dependencies, and test them without fakes.
- **`build` is pure.** It may run many times per second and at any moment, so it never starts a
  request, calls a controller's `load`, writes a field, or calls `setState`; it only describes the
  UI from the current state. Start effects in `initState`, in a listener or in an event handler
  (`onPressed`).
- **Make effects visible.** A method that does I/O returns a `Future` or `Stream` (see "Data
  providers"), and its dependencies come through the constructor, so a test can replace them.

## Law of Demeter

An object talks only to its direct collaborators: itself, its fields, its parameters and the objects
it creates. It does not reach through one of them to call the next (`a.b.c()`): that ties the
caller to how `a` is built, so changing `a`'s insides breaks code far away.

Breaking the law: the driver knows that a car has an engine and how to start it.

```dart
class Engine {
  void start() => print('Engine started');
}

class Car {
  final Engine engine = Engine();
}

class Driver {
  void drive(Car car) {
    car.engine.start(); // Reaches into the car.
  }
}
```

Following it: the car hides its engine behind its own method.

```dart
class Car {
  final Engine _engine = Engine();

  void start() => _engine.start(); // The car decides how it starts.
}

class Driver {
  void drive(Car car) {
    car.start();
  }
}
```

- In this architecture: a widget calls `controller.load()`, never `controller.repository.load()`; a
  controller asks its repository, never the repository's API client or database.
- Expose the action, not the part: add the method to the object that owns the part (`Car.start`)
  instead of making the part public.
- Data and value objects are exempt: reading `state.data.products` or `product.price.amount`
  navigates data, it does not command another object. Fluent APIs and builders (`a..b()..c()`,
  `query.where(...).orderBy(...)`) are exempt too.

## Examples

Whole files, one per block; put each where the layout above says and adjust the imports.

### `example.dart`

```dart
// file: example.dart
import 'package:flutter/foundation.dart';

/// A domain entity: immutable, final fields, `copyWith` for functional updates.
@immutable
class Example {
  /// Creates the entity.
  const Example({required this.id, required this.name, required this.description});

  /// Server id.
  final int id;

  /// Display name.
  final String name;

  /// Description text; `null` when the server sent none. Still `required`: see the Rules.
  final String? description;

  /// A copy with the given fields replaced. Nullable fields take a [ValueGetter], so passing
  /// `() => null` clears them while omitting the argument keeps the old value.
  Example copyWith({int? id, String? name, ValueGetter<String?>? description}) => Example(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description != null ? description() : this.description,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Example && other.id == id && other.name == name && other.description == description;

  @override
  int get hashCode => Object.hash(id, name, description);
}
```

### `example_config_widget.dart`

```dart
// file: example_config_widget.dart
import 'package:flutter/widgets.dart';

import 'dependencies.dart';
import 'example_controller.dart';
import 'example_data_controller.dart';
import 'example_repository.dart';

/// Gives the widgets below access to [ExampleConfigWidgetState].
class ExampleConfigInhWidget extends InheritedWidget {
  const ExampleConfigInhWidget({super.key, required this.state, required super.child});

  final ExampleConfigWidgetState state;

  static ExampleConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<ExampleConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'ExampleConfigInhWidget was not found in element tree');
    return (widget! as ExampleConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(ExampleConfigInhWidget oldWidget) => false;
}

/// Creates the feature's controllers in `initState`, disposes them in `dispose` and exposes them
/// through [ExampleConfigInhWidget]. The screen is built by [builder].
class ExampleConfigWidget extends StatefulWidget {
  const ExampleConfigWidget({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<ExampleConfigWidget> createState() => ExampleConfigWidgetState();
}

class ExampleConfigWidgetState extends State<ExampleConfigWidget> {
  late final ExampleController exampleController;
  late final ExampleDataController exampleDataController;

  @override
  void initState() {
    super.initState();
    final dependencies = DependenciesScope.of(context);
    exampleController = ExampleController(
      repository: ExampleRepositoryImpl(service: dependencies.exampleService),
    );
    exampleDataController = ExampleDataController();
    load();
  }

  @override
  void dispose() {
    exampleController.dispose();
    exampleDataController.dispose();
    super.dispose();
  }

  /// The active filter lives in the data controller and is passed on every call.
  void load() => exampleController.load(query: exampleDataController.query);

  @override
  Widget build(BuildContext context) =>
      ExampleConfigInhWidget(state: this, child: widget.builder(context));
}
```

### `example_controller.dart`

```dart
// file: example_controller.dart
import 'package:control/control.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'app_exception.dart';
import 'example.dart';
import 'example_repository.dart';

part 'example_controller.freezed.dart';

/// The four states of every controller, each carrying the examples the screen shows.
@freezed
sealed class ExampleState with _$ExampleState {
  const ExampleState._();

  const factory ExampleState.idle({@Default(<Example>[]) List<Example> examples}) =
      Example$IdleState;

  const factory ExampleState.processing({required List<Example> examples}) =
      Example$ProcessingState;

  const factory ExampleState.successful({required List<Example> examples}) =
      Example$SuccessfulState;

  const factory ExampleState.error({required List<Example> examples, required Object error}) =
      Example$ErrorState;

  /// A flag is a getter over the data, not a state.
  bool get isEmpty => examples.isEmpty;
}

/// Loads the examples. One controller, one domain concern; load and watch use
/// [SequentialControllerHandler] so calls never interleave.
final class ExampleController extends StateController<ExampleState>
    with SequentialControllerHandler {
  ExampleController({required this._repository, super.initialState = const ExampleState.idle()});

  final IExampleRepository _repository;

  /// The filter arrives as an argument on every call; the controller keeps no query field.
  void load({String query = ''}) => handle(() async {
    setState(ExampleState.processing(examples: state.examples));
    try {
      final examples = await _repository.examples(query: query);
      setState(ExampleState.successful(examples: examples));
    } on Object catch (error) {
      setState(ExampleState.error(examples: state.examples, error: error));
      // An expected answer is shown, not reported; anything else goes to the controller observer
      // through `handle` (see "Expected and unexpected errors" in docs/rules/controllers.md).
      if (error is! ExpectedException) rethrow;
    } finally {
      setState(ExampleState.idle(examples: state.examples));
    }
  });
}
```

### `example_data_controller.dart`

```dart
// file: example_data_controller.dart
import 'package:flutter/foundation.dart';

/// UI state of the example screen: the search text. Not asynchronous, so a plain [ChangeNotifier]
/// rather than a `StateController`. Widgets listen with `ListenableBuilder`.
class ExampleDataController with ChangeNotifier {
  String _query = '';

  /// The current search text.
  String get query => _query;

  /// Sets the search text and notifies listeners when it changed.
  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }
}
```

### `example_json_converter.dart`

```dart
// file: example_json_converter.dart
import 'dart:convert';

import 'example.dart';

/// Turns a response map into an [Example]. All API keys live here, not in widgets.
final class ExampleJsonConverter extends Converter<Map<String, Object?>, Example> {
  /// Creates the converter.
  const ExampleJsonConverter();

  @override
  Example convert(Map<String, Object?> input) => Example(
    // Backend numbers may arrive as int, double or String: parse tolerantly.
    id: int.tryParse('${input['id']}') ?? 0,
    name: '${input['name'] ?? ''}',
    description: input['description'] as String?,
  );
}
```

### `example_repository.dart`

```dart
// file: example_repository.dart
import 'example.dart';
import 'example_json_converter.dart';

/// Stand-in for the app's shared service (an API client, a database, the file system).
/// A real project already has one; the repository receives it through its constructor.
abstract interface class ExampleService {
  /// Reads [path] and returns the decoded JSON body.
  Future<Map<String, Object?>> get(String path, {Map<String, Object?>? queryParameters});
}

/// Reads examples. Controllers depend on this interface, so tests can pass a fake.
abstract interface class IExampleRepository {
  /// Examples whose name contains [query]; all of them when it is empty.
  Future<List<Example>> examples({String query = ''});
}

/// [IExampleRepository] over [ExampleService]. One simple source, so no data provider between the
/// two: the implementation sends the request and converts the response itself.
final class ExampleRepositoryImpl implements IExampleRepository {
  /// Creates the repository.
  ExampleRepositoryImpl({required this._service});

  final ExampleService _service;

  static const ExampleJsonConverter _converter = ExampleJsonConverter();

  @override
  Future<List<Example>> examples({String query = ''}) async {
    final body = await _service.get('/examples', queryParameters: {'q': query});
    final data = body['data'];
    if (data is! List<Object?>) return const <Example>[];
    return data.whereType<Map<String, Object?>>().map(_converter.convert).toList();
  }
}
```

### `example_widget.dart`

```dart
// file: example_widget.dart
import 'package:control/control.dart';
import 'package:flutter/material.dart';

import 'example_config_widget.dart';
import 'example_controller.dart';

/// The screen. It reads controllers from the config widget and never touches a repository.
class ExampleWidget extends StatefulWidget {
  const ExampleWidget({super.key});

  @override
  State<ExampleWidget> createState() => _ExampleWidgetState();
}

class _ExampleWidgetState extends State<ExampleWidget> {
  late final _scope = ExampleConfigInhWidget.of(context);
  late final _controller = _scope.exampleController;
  late final _dataController = _scope.exampleDataController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // A ChangeNotifier is observed with ListenableBuilder, not ValueListenableBuilder.
        // Visible text below is literal only to keep the template self-contained: in a project it
        // comes from `Localization.of(context)`.
        ListenableBuilder(
          listenable: _dataController,
          builder: (context, child) => TextField(
            onSubmitted: (value) {
              _dataController.setQuery(value);
              _scope.load();
            },
          ),
        ),
        Expanded(
          child: StateConsumer<ExampleController, ExampleState>(
            controller: _controller,
            // An error is a moment (the state is idle again right after): show it, with a retry,
            // from the listener.
            listener: (context, controller, oldState, newState) {
              if (newState is! Example$ErrorState) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Could not load the examples'),
                  action: SnackBarAction(label: 'Try again', onPressed: _scope.load),
                ),
              );
            },
            builder: (context, state, child) => switch (state) {
              Example$ProcessingState(:final examples) when examples.isEmpty => const Center(
                child: CircularProgressIndicator(),
              ),
              _ => ListView.builder(
                itemCount: state.examples.length,
                itemBuilder: (context, index) => ListTile(title: Text(state.examples[index].name)),
              ),
            },
          ),
        ),
      ],
    );
  }
}
```
