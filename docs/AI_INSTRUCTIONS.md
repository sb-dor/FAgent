# AI Instructions

## AI Identity

You are an expert in Flutter and Dart development. Your goal is to build beautiful, performant, and maintainable applications following modern best practices. You have expert experience with application writing, testing, and running Flutter applications for various platforms, including desktop, web, and mobile platforms.

## Token Economy

Be concise and efficient in every response. Do not repeat information the user already knows, do not summarize what you just did, do not add filler text or preamble. Go straight to the point. Only output what is necessary: code changes, brief status updates, blockers, or decisions that need input. Shorter responses are better than longer ones when both convey the same information.

---

# Flutter Architecture Analysis

## Overview

This document analyzes the clean architecture implementation in this Flutter application, focusing on the example feature as an example. The application follows a well-structured clean architecture pattern with clear separation of concerns.

---

## Project Structure

### Project `lib` Folder Structure

The `lib` folder must follow this top-level structure:

```
lib/
├── main.dart
└── src/
    ├── common/       # shared utilities, widgets, database, constants, etc.
    └── feature/      # one sub-folder per feature
```

**Rules:**

- `lib/main.dart` must always exist as the app entry point.
- `lib/src/` must always exist. All source code lives inside `src/` — nothing else goes directly under `lib/` except `main.dart`.
- `lib/src/common/` must always exist for shared code (database, router, constants, models, utilities, common widgets).
- `lib/src/feature/` must always exist and contains one sub-folder per feature.
- **If these folders already exist, do not recreate or restructure them.** Only create what is genuinely missing.
- Never place feature code directly under `lib/src/` — every feature gets its own named folder inside `lib/src/feature/`.

### Project Feature Conventions AI Must Follow

When creating or extending a feature, follow the structures below. Use the `example` naming pattern
as a placeholder for the real feature name. Do not invent a different architecture unless the existing
surrounding code already requires it.

#### List / Screen Feature Structure

A feature that loads and displays a list, dashboard, detail screen, or infinite-scroll table should look like:

```
example/
├── controller/
│   ├── example_controller.dart
│   └── example_controller.freezed.dart
├── data/
│   └── example_repository.dart
├── models/
│   ├── example.dart
│   ├── example_json_converter.dart
│   └── example_permissions.dart        # only when permissions are feature-specific
└── widgets/
    ├── controllers/
    │   └── example_data_controller.dart # filters/search/local UI state, only when needed
    ├── desktop/
    │   └── example_desktop_widget.dart
    ├── mobile/
    │   └── example_mobile_widget.dart
    └── example_config_widget.dart
```

Rules for this feature type:

- `example_config_widget.dart` creates controllers in `initState`, disposes them in `dispose`,
  and exposes them through `ExampleConfigInhWidget extends InheritedWidget`.
- `ExampleConfigWidgetState` owns `load()` and `paginate()` when the feature supports initial load
  and infinite scrolling.
- Load data after authentication with `AuthenticationInProgressListener` when identity or permissions are needed.
- Check permissions before loading data and before showing create/update/delete/picture/action buttons.
- Desktop UI lives in `widgets/desktop/`; mobile UI lives in `widgets/mobile/`.
- Use `context.screenSizeMaybeWhen(orElse: () => const ExampleMobileWidget(), desktop: () => const ExampleDesktopWidget())`.
- Add tablet only when there is a dedicated tablet UI.

#### Config Widget Navigation Pattern

Navigable features expose a static `open()` method from the config widget:

```dart
class ExampleConfigWidget extends StatefulWidget {
  const ExampleConfigWidget({super.key, this.example});

  static Future<void> open(
    BuildContext context, {
    Example? example,
    DesktopController? desktopController,
  }) async {
    context.screenSizeMaybeWhen(
      orElse: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ExampleConfigWidget(example: example)),
        );
      },
      desktop: () {
        desktopController?.setModule(
          exampleModule(example: example),
          clearModules: false,
        );
      },
    );
  }

  final Example? example;
}
```

Rules:

- Mobile navigation uses raw `Navigator.push(context, MaterialPageRoute(builder: (context) => ...))`.
  If the project provides a `MobileWebNavigator` helper, use `MobileWebNavigator.push(...)` instead of
  raw `Navigator.push(...)` so mobile-sized web works with the mobile browser-history logic.
- Desktop navigation must use `DesktopController.setModule(...)` and module factories.
- Module factories belong in `lib/src/feature/home/models/home_module_permission.dart`.
- Pass parameters through config widgets and module factories; do not use globals.
- Use `clearModules: false` for child/detail/create screens opened from another desktop module.
- If desktop temporarily opens another module for selecting an object, capture `currentModule` and
  return with `desktopController.breadCrumbModule(currentModule)` when the flow requires it.

#### Creation / Update Feature Structure

Create/update forms are separate features because their async save state is independent from list screens:

```
example_creation/
├── controller/
│   ├── example_creation_controller.dart
│   └── example_creation_controller.freezed.dart
├── data/
│   └── example_creation_repository.dart
└── widgets/
    ├── controllers/
    │   └── example_creation_data_controller.dart
    ├── desktop/
    │   └── example_creation_desktop_widget.dart
    ├── mobile/
    │   └── example_creation_mobile_widget.dart
    └── example_creation_config_widget.dart
```

Rules:

- Keep form state in `widgets/controllers/example_creation_data_controller.dart`.
- The data controller is a `ChangeNotifier` and stores an immutable draft object until save.
- Widgets read/write only through the data controller, then call `scope.save()`.
- The async controller uses `DroppableControllerHandler`.
- Create and update can share one controller and repository interface.
- If POST and PATCH differ, create separate repository implementations inside the same repository file,
  for example `ExampleCreationRepositoryImpl` and `ExampleUpdateRepositoryImpl`.
- If the form can open as a dialog, add an `openDialog()` factory and wrap the dialog body in
  `ScaffoldMessenger` so snackbar messages work.

#### Deletion Feature Structure

Delete actions are separate features:

```
example_deletion/
├── controller/
│   ├── example_deletion_controller.dart
│   └── example_deletion_controller.freezed.dart
├── data/
│   └── example_deletion_repository.dart
└── widgets/
    ├── example_deletion_config_widget.dart
    └── example_deletion_dialog_widget.dart
```

Rules:

- Use `DroppableControllerHandler` for the deletion controller.
- Config widget exposes a static `show(...)` method.
- Dialog widget uses `StateConsumer` and closes itself on `CompletedState`.
- Call the success callback before closing so the parent screen can reload.
- Use `AdaptiveDialogWidget` or the established local confirmation-dialog style.

Config widget example:

```dart
class ExampleDeletionConfigInhWidget extends InheritedWidget {
  const ExampleDeletionConfigInhWidget({required this.state, required super.child, super.key});

  final ExampleDeletionConfigWidgetState state;

  static ExampleDeletionConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<ExampleDeletionConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'ExampleDeletionConfigInhWidget was not found in widget tree');
    return (widget! as ExampleDeletionConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(covariant ExampleDeletionConfigInhWidget oldWidget) => false;
}

class ExampleDeletionConfigWidget extends StatefulWidget {
  const ExampleDeletionConfigWidget({
    super.key,
    required this.exampleId,
    required this.builder,
    this.onSuccessfullyDelete,
  });

  static Future<void> show(
    BuildContext context, {
    required int exampleId,
    VoidCallback? onSuccessfullyDelete,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ExampleDeletionConfigWidget(
        exampleId: exampleId,
        onSuccessfullyDelete: onSuccessfullyDelete,
        builder: (context) => const ExampleDeletionDialogWidget(),
      ),
    );
  }

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

Dialog widget example:

```dart
class ExampleDeletionDialogWidget extends StatefulWidget {
  const ExampleDeletionDialogWidget({super.key});

  @override
  State<ExampleDeletionDialogWidget> createState() => _ExampleDeletionDialogWidgetState();
}

class _ExampleDeletionDialogWidgetState extends State<ExampleDeletionDialogWidget> {
  late final _scope = ExampleDeletionConfigInhWidget.of(context);
  late final _controller = _scope.exampleDeletionController;
  late final _internetConnectionController = DependenciesScope.of(context).internetConnectionController;

  @override
  Widget build(BuildContext context) {
    return StateConsumer<ExampleDeletionController, ExampleDeletionState>(
      controller: _controller,
      listener: (context, controller, oldState, newState) {
        if (newState is ExampleDeletion$CompletedState) {
          _scope.onSuccessfullyDelete?.call();
          Navigator.pop(context);
        }
      },
      builder: (context, state, child) => AdaptiveDialogWidget(
        title: Localization.of(context).exampleDeletion,
        content: Localization.of(context).exampleDeletionConfirm,
        inProgress: state is ExampleDeletion$InProgressState,
        onConfirm: (_) {
          if (_internetConnectionController.value.isNotConnected) return;
          _controller.delete(
            _scope.exampleId,
            onMessage: (message) => showMessage(context, message: message),
          );
        },
      ),
    );
  }
}
```

#### By-Id Loader Feature Structure

Use this pattern when the caller has only an id, but the destination screen needs the full model:

```
example_by_id/
├── controller/
│   ├── example_by_id_controller.dart
│   └── example_by_id_controller.freezed.dart
├── data/
│   ├── example_by_id_repository.dart
│   └── example_json_converter.dart      # if the response shape needs a dedicated converter
└── widgets/
    ├── example_by_id_config_widget.dart
    └── example_by_id_edit_loader_widget.dart
```

Rules:

- **A detail screen loaded by id is its own feature**, separate from the list feature that links to it
  (e.g. `receipts` → `receipt_detail`). It has an independent controller, load state, and repository —
  the list controller and the detail controller never share a feature.
- Config widget receives the id, creates the by-id controller, and calls `load(id)` immediately.
- Loader widget listens for `CompletedState`, closes the loading dialog, then opens the destination
  view/edit screen.
- Mobile destination navigation uses `Navigator.push(context, MaterialPageRoute(builder: (context) => ...))`
  (or `MobileWebNavigator.push(...)` where that helper exists).
- Desktop destination navigation uses `desktopController.setModule(...)`.
- Error state shows `TryAgainButton(error: error, onPressed: () => controller.load(id))`.

#### Models and JSON Converters

Keep domain models and response parsing separated:

```
models/
├── example.dart
├── example_json_converter.dart
└── example_permissions.dart             # only when needed
```

Rules:

- Models use `@immutable` and final fields.
- Put API parsing in a `Converter<Map<String, Object?>, Example>` or a clearly named converter class.
- Keep snake_case API keys inside converters/repositories, not scattered through widgets.
- Use tolerant parsing for backend numeric fields that may arrive as `int`, `double`, or `String`
  (`double.tryParse('${json['amount']}')`, `int.tryParse('${json['id']}')`).
- Avoid unrelated private parsing helpers such as `_exampleFromJson` in widgets or repositories when the
  parsing belongs in `models/example_json_converter.dart`.
- For optional nullable fields in `copyWith`, use `ValueGetter<T?>?` so values can be explicitly cleared.

#### Local Database / Draft Tables

Only create a local Drift table when the task truly needs offline drafts or local persistence.

```
lib/src/common/database/tables/example_draft_table.dart
```

Rules:

- Table classes live in `lib/src/common/database/tables/`.
- Add the table import and table class to `@DriftDatabase(tables: [...])` in
  `lib/src/common/database/database.dart`.
- Bump `schemaVersion` in `lib/src/common/database/database.dart`.
- For actual Drift schema changes, add and keep the step-by-step migration file at
  `lib/src/common/database/database.steps.dart`.
- Check `lib/src/common/database/database.dart` again after generation and make sure it imports
  `lib/src/common/database/database.steps.dart` and uses the generated step-by-step migration strategy.
- Follow Drift's migration workflow when changing schema:
  [drift.simonbinder.eu/migrations](https://drift.simonbinder.eu/migrations/).
- Never edit `database.g.dart` manually.
- Run code generation after changing Drift tables.

Example migration pattern for `lib/src/common/database/database.dart`:

```dart
import 'package:flutter_project/src/common/database/database.steps.dart';

@override
int get schemaVersion => 2;

@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) => m.createAll(),
  onUpgrade: stepByStep(
    from1To2: (migrator, scheme) async {
      await migrator.create(scheme.exampleDraftTable);
    },
  ),
);
```

#### Localization

All visible widget text must use localization:

- Add every new user-facing key to both `lib/src/common/localization/intl_en.arb` and
  `lib/src/common/localization/intl_ru.arb`.
- Use `Localization.of(context).exampleKey` in widgets.
- Reuse existing keys before adding new ones.
- Do not hardcode English/Russian text in widgets except temporary debug-only text.
- Never manually edit generated localization files under `lib/src/common/localization/generated/`.

#### Reusable Widgets

If the same UI control appears in more than one feature, put it in `lib/src/common/widget/`.

Rules:

- Keep feature-specific UI inside the feature folder.
- Promote only genuinely reused controls to `common/widget`.
- Do not copy/paste common controls into every feature.
- Reuse existing common widgets for tables, filters, reset/cancel buttons, mobile action buttons,
  status pills, empty/error/loading states, image carousel/viewer, and shimmer placeholders.

### Feature Structure Analysis: Example

#### Directory Structure

```
example/
├── controller/
│   └── example_controller.dart
├── data/
│   └── example_repository.dart
├── models/
│   ├── example.dart
│   ├── example_other_1.dart
│   ├── example_other_2.dart
│   ├── example_other_3.dart
│   └── ...
└── widgets/
    ├── controllers/
    │   └── example_data_controller.dart
    ├── desktop/example_desktop_widget.dart
    ├── mobile/example_mobile_widget.dart
    ├── tablet/example_tablet_widget.dart
    └── example_config_widget.dart
```

#### Layer Integration

1. **UI Layer**: `example_config_widget.dart` initializes and manages feature controllers
2. **Presentation Layer**: `example_data_controller.dart` manages UI state
3. \*\*Business Logic Layer: `example_controller.dart` handles business logic and state
4. **Data Layer**: `example_repository.dart` handles data operations
5. **Model Layer**: `example.dart` represents domain entities

---

## Clean Architecture Layers

### 1. Data Layer (`data/`)

The data layer handles data operations and implements repositories that interact with external sources.

#### Example: `example_repository.dart`

```dart
// Interface definition
abstract interface class IExampleRepository {
  Future<List<Example>> example({...});
}

// Implementation
final class ExampleRepositoryImpl implements IExampleRepository {
  ExampleRepositoryImpl({required final ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<List<Example>> example({...}) async {
    // API call implementation
    final response = await _apiClient.get(endpoint, queryParameters: queryParameters);
    // Data transformation logic
  }
}
```

**Key Patterns:**

- Abstract interfaces for testability
- Dependency injection through constructor
- API client abstraction
- Data transformation using converters

#### No datasource layer

Do **not** add a separate `*_datasource.dart` between the repository and the API
client. One interface + one implementation per repository is the whole data
layer. The repository implementation receives the `ApiClient` (and any other
shared services) through its constructor and performs the request **and**
conversion directly.

```dart
final class ExampleRepositoryImpl implements IExampleRepository {
  ExampleRepositoryImpl({required this._apiClient});
  final ApiClient _apiClient;

  @override
  Future<List<Example>> example({...}) async {
    final response = await _apiClient.get(_path, queryParameters: {...});
    final data = response.body['data'];
    if (data is! List) return const [];
    return data.whereType<Map<String, Object?>>().map(_converter.convert).toList();
  }
}
```

#### App-global scope values are read by the repository, not threaded through layers

A value that is app-global scope state — the selected store (`store_uid`), the
active organisation, the current warehouse — is **read inside the repository**,
not passed down from the widget through the controller. The repository takes
`SharedPreferences` (or the relevant scope service) in its constructor and reads
the value per call; e.g. store-scoped report repositories use
`readSelectedStoreUid(prefs)` from `lib/src/common/utils/owner_selected_store.dart`.
Only per-screen query parameters (filters, search terms, ids) travel through
`load(...)` / `paginate(...)`.

### Stream-Returning Methods in Repositories

Repository methods that return `Stream<T>` must always guarantee the stream is eventually closed. Never return a bare `StreamController.stream` without a close path — it leaks resources.

#### Pattern 1 — `onListen` / `onCancel` (lazy, resource-safe)

Code runs only when someone starts listening. Resources are released when the subscriber cancels.

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

Add a mutex or boolean flag to guarantee `close()` is never called while `onListen` is still executing, and to break any loop inside `onListen` when cancellation occurs.

#### Pattern 2 — `async Future` wrapper (simpler, more readable)

The entire emission logic lives in an async closure. The `finally` block guarantees `close()` is always called.

```dart
Stream<R> fn() {
  final controller = StreamController<R>();
  Future<void>(() async {
    try {
      // Your emission logic here, e.g. a for(;;) loop.
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

The async body can also be placed entirely inside `onListen` instead of a standalone `Future`.

#### One-shot helpers

For simple cases prefer the built-in constructors over a manual controller:

```dart
Stream.value(r)               // single value then done
Stream.fromFuture(future)     // single async value then done
Stream.fromFutures([f1, f2])  // multiple async values then done
```

#### Rule

Every `Stream`-returning repository method must use one of the patterns above. A `StreamController` with no guaranteed `close()` path is always wrong.

---

### 2. Model Layer (`models/`)

Models represent business entities and are immutable.

#### Example: `example.dart` (optional)

```dart
@immutable
class Example {
  const Example({
    required this.id,
    this.exampleId,
    this.example,
    // ... other properties
  });

  // Properties
  final int id;
  final int? exampleId;
  // ... other fields

  // Copy with method for immutability
 Example copyWith({...}) {
    return Example(
      id: id ?? this.id,
      // ... other fields
    );
  }
}
```

**Key Patterns:**

- Immutable design with `@immutable` annotation
- `copyWith` method for functional updates

### Model CopyWith Pattern

For models that use the `copyWith` method, they must use the `ValueGetter` function from the foundation package for optional parameters. This ensures proper null-safety and functional updates:

```dart
Example copyWith({
  int? id,
  ValueGetter<double?>? parameter_1,
  ValueGetter<double?>? parameter_2,
  ValueGetter<double?>? invoicesQty,
  ValueGetter<double?>? returnsTotal,
  ValueGetter<double?>? returnsQty,
  ValueGetter<double?>? paymentsTotal,
  ValueGetter<double?>? paymentsQty,
  ValueGetter<double?>? grandTotal,
  // ... other parameters
}) {
  return Example(
    id: id ?? this.id,
    parameter_1: parameter_1 != null ? parameter_1() : this.parameter_1,
    parameter_2: parameter_2 != null ? parameter_2() : this.parameter_2,
    invoicesQty: invoicesQty != null ? invoicesQty() : this.invoicesQty,
    returnsTotal: returnsTotal != null ? returnsTotal() : this.returnsTotal,
    returnsQty: returnsQty != null ? returnsQty() : this.returnsQty,
    paymentsTotal: paymentsTotal != null ? paymentsTotal() : this.paymentsTotal,
    paymentsQty: paymentsQty != null ? paymentsQty() : this.paymentsQty,
    grandTotal: grandTotal != null ? grandTotal() : this.grandTotal,
    // ... assign other parameters
  );
}
```

---

### 3. Controller Layer (`controller/`)

Controllers manage state and business logic using reactive programming patterns.

#### Example: `example_controller.dart` (required)

```dart
@freezed
sealed class ExampleState with _$ExampleState {
  const factory ExampleState.initial() = Example$InitialState;

  const factory ExampleState.inProgress() = Example$InProgressState;

  const factory ExampleState.error() = Example$ErrorState;

  const factory ExampleState.completed({...}) =
      Example$CompletedState;
}

final class ExampleController extends StateController<ExampleState>
    with SequentialControllerHandler {
  ExampleController({
    required final IExampleRepository exampleRepository,
    super.initialState = const ExampleState.initial(),
  }) : _iExampleRepository = exampleRepository;

  final IExampleRepository _iExampleRepository;

  void load({...}) => handle(() async {
    setState(const ExampleState.inProgress());

    final example = await _iExampleRepository.example({...});

    setState(
      ExampleState.completed(),
    );
  }, error: (error, stackTrace) async => setState(const ExampleState.error()));
}
```

**Key Patterns:**

- Freezed for immutable state management
- Dependency injection through constructor
- Sequential handling to prevent race conditions
- State management with loading/error/completed states

### Single Responsibility Principle for Features and Controllers

Every feature folder and every controller must have **one clearly defined domain responsibility**. A responsibility is not a single function — it is a single domain concern.

#### What "one responsibility" means

A controller may have multiple methods as long as they all serve the same domain concern:

```dart
// ✅ Correct — AuthenticationController has one responsibility: managing auth state.
// signIn, signOut, checkToken all answer the same question: "is this user authenticated?"
class AuthenticationController {
  void signIn({required String username, required String password}) => ...
  void signOut() => ...
  void checkToken() => ...
}
```

This is fine. All three methods are facets of the same concern. Splitting them into three separate features would be over-engineering.

#### When to split into separate features

Split when two things have **genuinely independent UI state machines** or **no logical connection at the domain level**.

The quick replies functionality is split into three features because each has a distinct concern:

```
example_list/          → "Provide the reactive list of quick replies to the UI"
example_creation/   → "Manage the create/edit form lifecycle (inProgress, completed, error)"
example_deletion/   → "Manage the delete confirmation lifecycle (inProgress, completed, error)"
```

The creation form and the deletion dialog each need their own `inProgress` / `completed` / `error` state independently. If they shared one controller, a deletion in progress could overwrite the creation form's state — causing wrong UI feedback and broken `PopScope` behaviour. The list (watching a stream) has no state overlap with either mutation. These are separate concerns, so they are separate features.

#### The pattern for mutation features (creation, deletion)

Each mutation feature follows this exact structure:

```
feature_name/
├── data/feature_name_repository.dart      (interface + impl)
├── controller/feature_name_controller.dart (freezed states + handle())
└── widgets/
    ├── feature_name_config_widget.dart    (InheritedWidget scope + static factory)
    └── feature_name_dialog_widget.dart    (form/confirmation UI)
```

**Controller** uses `DroppableControllerHandler` for mutations so duplicate taps are dropped:

```dart
class ExampleCreationController extends StateController<ExampleCreationState>
    with DroppableControllerHandler {

  void save({required String title, required String content, int? workerId, Example? existing}) =>
      handle(() async {
        setState(const ExampleCreationState.inProgress());
        final result = await _repo.save(title: title, content: content, existing: existing);
        setState(ExampleCreationState.completed(result));
      }, error: (e, st) async => setState(const ExampleCreationState.error()));
}
```

Use `SequentialControllerHandler` for load/watch operations.

**Config widget** owns the controller lifecycle and exposes a static factory so callers need only one line:

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

**Dialog widget** uses `StateConsumer` to close itself on completion and `PopScope` to block dismissal mid-flight:

```dart
StateConsumer<ExampleCreationController, ExampleCreationState>(
  controller: _controller,
  listener: (context, controller, oldState, newState) {
    if (newState is ExampleCreation$CompletedState) Navigator.pop(context);
  },
  builder: (context, state, child) => PopScope(
    canPop: state is! ExampleCreation$InProgressState,
    child: AlertDialog(...),
  ),
);
```

**Calling site** only uses the static factory — no knowledge of internals:

```dart
ExampleCreationConfigWidget.showCreationDialog(context);
ExampleCreationConfigWidget.showCreationDialog(context, existing: example);
ExampleDeletionConfigWidget.showDeletionDialog(context, example);
```

#### Rules to always follow

- **Group by domain concern, not by function count.** A controller with three related methods is fine. A controller with two unrelated concerns must be split.
- **Create and update may share one feature** when they are conceptually the same action (both write the same record). The create-vs-update decision belongs in the repository, not the controller or widget.
- **Split when UI states are independent.** If two operations each need their own `inProgress` / `completed` / `error` displayed simultaneously or to different widgets, they need separate controllers and separate features.
- **Config widgets own controller lifecycle** — created in `initState`, disposed in `dispose`, never elsewhere.
- **Static factory methods on config widgets** keep all wiring internal and give callers a one-line API.
- **`DroppableControllerHandler`** for mutations. **`SequentialControllerHandler`** for load/watch.
- **`PopScope(canPop: state is! ...InProgressState)`** on every dialog with an async operation.

### Multiple Controllers per Feature

When a feature contains async operations with **different concurrency requirements**, split them into separate controllers — one per async concern. This is correct architecture, not over-engineering.

#### When to split controllers within one feature

Split when two groups of async operations:

- Need different concurrency handlers (`DroppableControllerHandler` vs `SequentialControllerHandler`), or
- Maintain genuinely independent state that must update simultaneously without one overwriting the other.

#### Example — call feature

```
call/controller/
├── call_controller.dart
├── call_media_controller.dart
└── call_members_controller.dart
```

Each controller handles one async concern. `CallMediaController` uses `Droppable` so rapid taps are dropped. `CallController` uses `Sequential` so join and leave are never interleaved. Sharing one controller would force a single concurrency strategy on all three — wrong for at least two of them.

#### Coordination rule

Controllers within the same feature must **never import or depend on each other**. Coordinate them in the **widget layer** via `addListener` or `StateConsumer`'s `listener` parameter. The widget reacts to one controller's state and calls methods on another.

```dart
// ✅ Widget layer coordinates — controllers stay decoupled
callController.addListener(() {
  if (callController.state is Call$IdleState) {
    callMembersController.reset();
    callMediaController.reset();
  }
});
```

---

### 4. Widgets Layer (`widgets/`)

The presentation layer handles UI rendering and user interaction.

Config-widget scope, responsive screen selection, and static navigation factories are defined in the
feature-conventions section above.

**Widget type rules:**

- Use `StatefulWidget` for complex widgets, parent/root feature widgets, and widgets that own
  controllers, listeners, scroll state, text controllers, focus nodes, animations, or non-trivial
  callbacks.
- Use `StatelessWidget` for small presentational widgets, usually under 30-50 lines, that only render
  values passed through the constructor.
- When unsure for a parent widget, prefer `StatefulWidget`.

**Widget file-size and splitting rules:**

- Keep `*_desktop_widget.dart` and `*_mobile_widget.dart` as screen composition files, not long files
  containing every card, row, filter, dialog section, and helper widget.
- Split complex UI into focused Dart files inside the same `widgets/desktop/`, `widgets/mobile/`, or
  nearby feature widget folder. Example:

```text
widgets/
└── mobile/
    ├── example_mobile_widget.dart
    ├── example_mobile_header.dart
    ├── example_mobile_filter_bar.dart
    ├── example_mobile_card.dart
    └── example_mobile_actions.dart
```

- Do not use `part` / `part of` for widget splits. Create normal Dart files and import them.
- Prefer small private widgets in the same file only when the screen remains readable. If the file
  grows large, move those widgets into separate files even if they are used by only one screen.
- Keep business logic in controllers/scopes/data controllers. Extracted widget files should receive
  values and callbacks through constructors instead of reaching into unrelated layers.

#### Example: `example_config_widget.dart`

```dart
/// Inherited widgets that provides access to ExampleConfigWidgetState throughout the widgets tree.
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
  bool updateShouldNotify(ExampleConfigInhWidget old) {
    return false;
  }
}

class ExampleConfigWidget extends StatefulWidget {
  const ExampleConfigWidget();
  // Implementation details

  @override
  State<ExampleConfigWidget> createState() => ExampleConfigWidgetState();
}

class ExampleConfigWidgetState extends State<ExampleConfigWidget> {
  // Controller initialization and lifecycle management
  late final ExampleController exampleController;

  @override
  void initState() {
    super.initState();
    final dependencies = DependenciesScope.of(context);
    _authenticationController = dependencies.authenticationController;
    _authenticationListener();
    _authenticationController.addListener(_authenticationListener);
  }

  @override
  void dispose() {
    _authenticationController.removeListener(_authenticationListener);
    exampleController.dispose();
    super.dispose();
  }

  void _authenticationListener() {
    // Initialize controller based on authentication state
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? const Center(child: CircularProgressIndicatorWidget())
        : ExampleConfigInhWidget(
            state: this,
            child: context.screenSizeMaybeWhen(
              orElse: () => const ExampleDesktopWidget(),
              phone: () => const ExampleMobileWidget(),
            ),
          );
  }
}
```

**Key Patterns:**

- InheritedWidget for dependency propagation
- Proper lifecycle management with disposal
- Responsive UI based on screen size
- Authentication-aware initialization

#### Example: `example_data_controller.dart` (UI State Management)

```dart
class ExampleDataController with ChangeNotifier {
  ///
  ///
  /// not optional - it's just for an example
  String? _from;

  String? _to;

  String? get from => _from;

  String? get to => _to;

  final List<Example> _selectedExamples = [];

  List<Example> get selectedExamples => _selectedExamples;

  void addExample(final Example example) {
    _selectedExamples.add(example);
    notifyListeners()
  }
}
```

**Key Patterns:**

- Uses `ChangeNotifier` mixin for UI state management
- Different from `example_controller.dart` which manages asynchronous operations and application state
- `example_data_controller.dart` specifically manages UI-related state
- Provides getter methods for accessing state values
- Uses `notifyListeners()` to trigger UI updates when state changes
- Includes proper lifecycle management with disposal considerations
- Do not use other state solutions like these packages: Provider, Riverpod, Mobx, Getx, BloC for UI state management for widgets folder

### Accessing Dependencies Through Inherited Widgets

To access dependencies that were initialized inside the `ExampleConfigWidget`, use the `ExampleConfigInhWidget.of(context)` pattern. For example, if you have an `ExampleMobileWidget` that needs to access the `ExampleDataController` initialized in the `ExampleConfigWidget`:

```dart
class ExampleMobileWidget extends StatefulWidget {
  const ExampleMobileWidget({super.key});

  @override
  State<ExampleMobileWidget> createState() =>
      _ExampleMobileWidgetState();
}

class _ExampleMobileWidgetState
    extends State<ExampleMobileWidget> {
  late final _exampleInhWidget = ExampleConfigInhWidget.of(
    context,
  );

  late final _exampleDataController =
      _exampleInhWidget.exampleDataController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _exampleDataController,
      builder: (context, child) {
        // Build UI based on the controller's state
        return Container(
          // Your widget implementation
        );
      },
    );
  }
}
```

### Modern Dart Constructor Syntax

Use the modern Dart syntax for calling the parent constructor in the super parameter. Instead of the old approach of extending child constructors with explicit `super()` calls, you can now use the `super()` named parameter directly:

```dart
// Modern approach
const ExampleMobileWidget({super.key});

// Rather than the older approach which required more verbose syntax
```

### Using ListenableBuilder for ChangeNotifier

When listening to an `ExampleDataController` (which extends `ChangeNotifier`), use `ListenableBuilder` instead of `ValueListenableBuilder`. `ListenableBuilder` is designed for objects that extend `Listenable` (like `ChangeNotifier`), while `ValueListenableBuilder` is specifically for `ValueNotifier`:

```dart
// Correct approach for ChangeNotifier
ListenableBuilder(
  listenable: exampleDataController,
  builder: (context, child) {
    // Return your widget here
    return YourWidget();
  },
)

// Rather than ValueListenableBuilder which is for ValueNotifier
```

---

## Dependency Injection Patterns

### Global Dependency Injection

The application uses a global dependency injection system through `DependenciesScope`:

#### `Dependencies` Class

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
```

#### `DependenciesScope` Widget

```dart
class DependenciesScope extends InheritedWidget {
  const DependenciesScope({required this.dependencies, required super.child, super.key});

  final Dependencies dependencies;

  static Dependencies of(BuildContext context) =>
      maybeOf(context) ?? _notFoundInheritedWidgetOfExactType();

  @override
  bool updateShouldNotify(covariant DependenciesScope oldWidget) => false;
}
```

### Feature-Level Dependency Injection

Features use their own configuration widgets to initialize and provide controllers:

#### `example_config_widget.dart` (Dependency Initialization)

```dart
void _authenticationListener() {
  final authenticationState = _authenticationController.state;
  if (authenticationState is Authentication$AuthenticatedState && isLoading) {
    /// initializations for Authanticated state
  }
}
```

### Scope Management with Inherited Widgets

#### InheritedWidget Pattern

The application uses InheritedWidget for efficient state propagation:

```dart
// Custom InheritedWidget for feature-specific state
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
  bool updateShouldNotify(ExampleConfigInhWidget old) {
    return false; // Prevent unnecessary rebuilds
 }
}
```

#### Global Scope with DependenciesScope

Global dependencies are provided through the DependenciesScope:

```dart
// In main app setup
dependencies.inject(child: MaterialApp(...))

// In widgets accessing dependencies
final deps = DependenciesScope.of(context);
```

### Interface Usage and DI Concepts

#### Interface-Based Design

The application extensively uses interfaces for loose coupling:

```dart
// Repository interfaces
abstract interface class IExampleRepository {...}
abstract interface class IProductsRepository {...}
abstract interface class IExampleBalanceRepository {...}

// Controller interfaces (when applicable)
```

#### Constructor-Based Dependency Injection

Dependencies are injected through constructors:

```dart
// Repository implementation receives API client
ExampleRepositoryImpl({required final ApiClient apiClient}) : _apiClient = apiClient;

// Controller receives repository interface
ExampleController({
  required final IExampleRepository exampleRepository,
  // ...
})

// Widget receives dependencies through scope
dependencies = DependenciesScope.of(context);
```

---

## Paginated Controllers — the canonical shape

Every paged list in this app follows one shape. Copy it rather than inventing a
variant; the differences between hand-rolled paginators are exactly where the
silent bugs live.

### The rules

1. **The cursor lives in the state, never in a controller field.** `page` and
   `hasMore` are constructor arguments of the `completed` state. A mutable
   `int _page` on the controller can be advanced past a page that failed, which
   puts a permanent, invisible hole in the list — the rows between the failed
   page and the next one are simply never fetched, and nothing on screen says so.
   With the cursor in the state there is no counter to desynchronise.
2. **Everything the controller depends on arrives through the constructor** —
   the repository, the page size, the pagination util, the initial filter. A
   dependency constructed inside the controller cannot be substituted in a test
   and cannot be varied per screen.
3. **`page` in the completed state is the *next* page to request**, not the one
   just loaded. `LocalPaginationUtil.checkIsListHasMorePageInt` computes it.

`LocalPaginationUtil` lives at `lib/src/common/utils/local_pagination_util.dart`.
It infers "has more" from **page fullness** — a full page (length ==
`limitInPage`) means another page probably exists; a short page means the end. No
server `total` is required; keep `total` in the state only when the UI shows a
count.

Two further rules that fall out of the shape:

4. **Two methods, never one.** `load(...)` fetches page 1 and resets state;
   `paginate(...)` appends the next page. Both run through the same
   `SequentialControllerHandler` so they never interleave.
5. **The async controller stays query-stateless.** It holds no `_query` /
   `_from` / `_storeUid` fields. The active query and filters live in a
   `ChangeNotifier` **data controller** under `widgets/controllers/` (e.g.
   `example_data_controller.dart`); the config widget reads them and passes them
   into `load(...)` / `paginate(...)` on every call. App-global scope values such
   as `store_uid` are not passed at all — the repository reads them itself (see
   the Data Layer rule above). Echoing the active query back into the `completed`
   state is a display concern and is fine; storing it as a mutable controller
   field is not.

### The template

```dart
@freezed
sealed class ProductsState with _$ProductsState {
  const factory ProductsState.initial() = Products$InitialState;
  const factory ProductsState.inProgress() = Products$InProgressState;
  const factory ProductsState.error({final Object? error}) = Products$ErrorState;

  /// [page] is the NEXT page to request; [query] is the active search term.
  const factory ProductsState.completed(
    final List<Product> products,
    final int page,
    final bool hasMore,
    final int total,
    final String query,
  ) = Products$CompletedState;
}

final class ProductsController extends StateController<ProductsState>
    with SequentialControllerHandler {
  ProductsController({
    required this._productsRepository,
    final LocalPaginationUtil? localPaginationUtil,
    this._limitInPage = 50,
    super.initialState = const ProductsState.initial(),
  }) : _localPaginationUtil = localPaginationUtil ?? LocalPaginationUtil();

  final IProductsRepository _productsRepository;
  final LocalPaginationUtil _localPaginationUtil;
  final int _limitInPage;

  void load({String query = '', int? categoryId}) => handle(() async {
    setState(const ProductsState.inProgress());
    final (items, total) = await _productsRepository.products(
      categoryId: categoryId,
      query: query,
      page: 1,
      pageSize: _limitInPage,
    );
    setState(ProductsState.completed(items, _nextPage(items, 1), _hasMore(items), total, query));
  }, error: (error, stackTrace) async => setState(ProductsState.error(error: error)));

  void paginate({String query = '', int? categoryId}) => handle(() async {
    if (state is! Products$CompletedState) return;
    final current = state as Products$CompletedState;
    if (!current.hasMore) return;
    final (next, total) = await _productsRepository.products(
      categoryId: categoryId,
      query: query,
      page: current.page,
      pageSize: _limitInPage,
    );
    setState(
      ProductsState.completed(
        [...current.products, ...next],
        _nextPage(next, current.page),
        _hasMore(next),
        total,
        query,
      ),
    );
  }, error: (error, stackTrace) async => setState(ProductsState.error(error: error)));

  int _nextPage(List<Product> list, int page) => _localPaginationUtil.checkIsListHasMorePageInt(
    list: list,
    page: page,
    limitInPage: _limitInPage,
  );

  bool _hasMore(List<Product> list) =>
      _localPaginationUtil.checkIsListHasMorePageBool(list: list, limitInPage: _limitInPage);
}
```

`SequentialControllerHandler`, always — a second page request arriving while the
first is in flight must run, not be dropped. `paginate`'s `hasMore` guard is what
makes the repeated firing of a bottom-of-list scroll notification safe.

The matching repository returns the page **and the server's total** as a record,
and reads its own scoped values rather than having them threaded down:

```dart
typedef ProductsPage = (List<Product> products, int total);

abstract interface class IProductsRepository {
  Future<ProductsPage> products({
    String? query,
    int? categoryId,
    required int page,
    required int pageSize,
  });
}
```

### Convenience getters on the state

Put shared accessors on the sealed state, not the controller — `CustomersState`
does this with `allCustomers` / `selectableCustomers`. Add `const XxxState._();`
to the union so it can carry methods.

⚠️ **A getter that shares a name with a variant's field is overridden by that
field.** `completed` declares `entries` / `page` / `hasMore`; a base getter of the
same name is reached only for the variants that *don't* declare it. Writing it as
an exhaustive `switch (this)` with a `completed` arm compiles, reads plausibly,
and that arm is dead code. Write the body as the answer for the variants without
the field:

```dart
List<Product> get products => const <Product>[];   // completed's field wins
bool get hasMore => false;
```

Give a getter a *different* name from the fields when it needs to compute across
them — `allCustomers` reads `customers`, which is why it works.

### Triggering `paginate` from the widget

The widget fires `paginate()` from a `ScrollController` near the bottom of the
list, guarded by `controller.isProcessing` (exposed by
`SequentialControllerHandler`) so a burst of scroll notifications fires only one
fetch. Show a footer spinner while `hasMore`.

The active filter lives in the data controller; the config widget owns both
controllers and threads the filter through on every call:

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

An endpoint that truly returns a single fixed or capped list (a small summary
feed, a hard top-N with no page controls) does **not** use this pattern: fetch it
in one `load()` and render it, with no `paginate()`. When in doubt, add
pagination — most list endpoints here accept `page` / `page_size`.

### Optional refinements, where the screen earns them

* **`paginate` must not set `inProgress`.** Leave the `completed` state in place
  until the next page lands. Paging happens while a user is scrolling, and an
  `inProgress` with no rows blanks the list under them mid-scroll. `load` is the
  opposite case and should clear: its rows no longer answer the question asked.
* **A pagination failure clears the whole list.** The cursor lives on `completed`,
  so an error takes it with it and the failed page cannot be resumed — recovery is
  `load()` from page 1. That is the right trade: a page of a list with the rest
  silently missing reads as the whole list.
  The alternative — restoring the previous `completed` state on a `paginate`
  failure so the rows already on screen survive — is acceptable only when the
  screen surfaces the failure explicitly (an inline retry footer). Silently
  keeping a truncated list with no error affordance is the case this rule exists
  to prevent.
* **Echo the active filter/query in the completed state** when the app bar has to
  show how many facets are on. The controller still takes the *initial* one
  through its constructor and falls back to it outside `completed`.
* **Echo the active filter in the state** when the app bar has to show how many
  facets are on. The controller still takes the *initial* filter through its
  constructor; the per-call argument is what the screen passes on apply.

For a worked example of both, see
`lib/src/feature/change_log/controller/change_log_controller.dart`.

---

## Best Practices Observed

### 1. Separation of Concerns

- Each layer has a clear responsibility
- Models handle data representation
- Controllers manage business logic and state
- Repositories handle data operations
- Widgets handle presentation

#### Strict Layer Dependency Rule

Within a single feature, the dependency direction is strictly one-way:

```
widgets  →  controller  →  data (repository)
```

**Widgets must never access repositories directly.** All data operations go through the controller. The controller is the only layer that depends on the data layer. Widgets depend only on the controller layer.

**Wrong — widget accessing repository directly:**

```dart
// ❌ NEVER do this inside a widget or widget state
class _MyWidgetState extends State<MyWidget> {
  @override
  void initState() {
    super.initState();
    final deps = Dependencies.of(context);
    // Directly calling a repository from a widget — violates separation of concerns
    deps.someRepository.loadData();
  }
}
```

**Correct — widget depends only on controller:**

```dart
// ✅ Correct approach
class _MyWidgetState extends State<MyWidget> {
  late final _scope = MyConfigInhWidget.of(context);
  late final _controller = _scope.myController;

  @override
  void initState() {
    super.initState();
    _controller.load(); // controller handles all data access internally
  }
}
```

The controller encapsulates all repository calls. If a widget needs data (e.g. quick replies, workers, settings), that data must be fetched inside the controller and exposed via state or a getter — never fetched by the widget itself.

This rule applies everywhere: `StatefulWidget` states, `StatelessWidget` build methods, `InheritedWidget` config states, and data controllers (`ChangeNotifier`-based UI controllers). None of these should hold a reference to any `Repository` class.

### 2. Testability

- Interface-based design enables mocking
- Constructor injection enables easy testing
- Immutable models reduce side effects

### 3. Maintainability

- Consistent naming conventions
- Clear directory structure
- Proper separation of business logic from UI

### 4. Performance

- Efficient InheritedWidget usage
- Proper disposal of resources
- Lazy loading where appropriate

---

## Development Notes

### Generated Files

When working with this architecture, be aware of generated Dart files that should be ignored in version control and manual editing:

- Files ending with `.freezed.dart` (generated by the `freezed` package)
- Files ending with `.g.dart` (generated by various packages like `json_annotation`, `injectable`, etc.)
- Files ending with `.gen.dart` (e.g. FlutterGen asset classes)
- Generated localization files under `lib/src/common/localization/generated/`
- Other generated files following the pattern `[filename].generated.dart`

These files should be added to your `.gitignore` file and should never be manually modified, as they are automatically regenerated by build runners.

### Build Runner Command

After creating a new feature or making changes that require code generation, run build runner.
This is required when any touched file includes or introduces:

- `@freezed`
- `freezed` state/model declarations
- `part 'example.freezed.dart';`
- `part 'example.g.dart';`
- Drift tables or database annotations
- JSON serialization annotations
- FlutterGen/pubspec generated assets
- Any other annotation, `part`, or generated-code marker that depends on build runner

```bash
dart run build_runner build --delete-conflicting-outputs && dart format lib/
```

This command generates Freezed classes, JSON serializers, Drift files, and other generated code.

Never manually edit generated files such as `*.freezed.dart`, `*.g.dart`, `*.gen.dart`, or files under
`lib/src/common/localization/generated/`.

---

## Conclusion

This Flutter application demonstrates a well-implemented clean architecture with:

- Clear separation of concerns across data, domain, and presentation layers
- Comprehensive dependency injection using both global and feature-level approaches
- Effective use of InheritedWidget for state management and dependency propagation
- Consistent patterns across all features
- Proper lifecycle management and resource disposal

The example feature serves as an excellent example of how the architecture principles are applied consistently throughout the application, maintaining scalability and maintainability while following Flutter best practices.
