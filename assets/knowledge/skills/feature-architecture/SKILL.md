---
name: feature-architecture
description: "Scaffold or extend a feature with the project's layers: models, data (repository), controller, widgets; list, creation, deletion and by-id features."
when_to_use: "When adding a new feature folder, screen, controller or repository, or when deciding where code belongs."
version: "2.0"
---

# Feature architecture

## Project structure

```
lib/
├── main.dart
└── src/
    ├── common/       # shared utilities, widgets, database, constants, localization
    └── feature/      # one sub-folder per feature
```

- `lib/main.dart`, `lib/src/`, `lib/src/common/` and `lib/src/feature/` always exist. Nothing but
  `main.dart` sits directly under `lib/`; no feature code directly under `lib/src/`.
- If these folders already exist, do not recreate or restructure them. Create only what is missing.
- Use `example` as a placeholder for the real feature name. Do not invent another architecture
  unless the surrounding code already requires it.

## Layers and dependency direction

1. **UI**: `example_config_widget.dart` creates and owns the controllers.
2. **UI state**: `example_data_controller.dart` (a `ChangeNotifier`) holds filters, search, selection.
3. **Business logic**: `example_controller.dart` runs async work and holds `StateController` state.
4. **Data**: `example_repository.dart` talks to the API, database, files.
5. **Models**: `example.dart` is the domain entity.

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

## List / screen feature

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
`example_widget.dart` (flat folder; adjust the relative imports to the feature layout).

### Config widget navigation

A navigable feature exposes a static `open()` from its config widget:

```dart
static Future<void> open(BuildContext context, {Example? example, DesktopController? desktopController}) async {
  context.screenSizeMaybeWhen(
    orElse: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ExampleConfigWidget(example: example)),
    ),
    desktop: () => desktopController?.setModule(exampleModule(example: example), clearModules: false),
  );
}
```

- Mobile navigation is `Navigator.push(context, MaterialPageRoute(builder: ...))`. If the project has
  a `MobileWebNavigator` helper, use `MobileWebNavigator.push(...)` so mobile-sized web keeps its
  browser-history logic.
- Desktop navigation, when the project has a desktop shell, goes through
  `DesktopController.setModule(...)` and module factories. Module factories belong in the project's
  home-module file (for example `lib/src/feature/home/models/home_module_permission.dart`).
- Pass parameters through config widgets and module factories; no globals.
- `clearModules: false` for child/detail/create screens opened from another desktop module. If a
  module is opened to pick an object, capture `currentModule` and return with
  `desktopController.breadCrumbModule(currentModule)`.

## Creation / update feature

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

## Deletion feature

```
example_deletion/
├── controller/example_deletion_controller.dart
├── data/example_deletion_repository.dart
└── widgets/
    ├── example_deletion_config_widget.dart
    └── example_deletion_dialog_widget.dart
```

- `DroppableControllerHandler`. The config widget exposes a static `show(...)`.
- The dialog uses `StateConsumer` and closes itself on `CompletedState`. Call the success callback
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
    if (newState is ExampleDeletion$CompletedState) {
      _scope.onSuccessfullyDelete?.call();
      Navigator.pop(context);
    }
  },
  builder: (context, state, child) => AdaptiveDialogWidget(
    title: Localization.of(context).exampleDeletion,
    content: Localization.of(context).exampleDeletionConfirm,
    inProgress: state is ExampleDeletion$InProgressState,
    onConfirm: (_) => _controller.delete(
      _scope.exampleId,
      onMessage: (message) => showMessage(context, message: message),
    ),
  ),
)
```

Runnable pieces: skill `controller-patterns` (`example_deletion_controller.dart`,
`example_deletion_dialog.dart`).

## By-id loader feature

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
- The loader widget listens for `CompletedState`, closes the loading dialog, then opens the
  destination view/edit screen (mobile `Navigator.push`, desktop `desktopController.setModule`).
- Error state shows `TryAgainButton(error: error, onPressed: () => controller.load(id))`.

## Models and JSON converters

```
models/
├── example.dart
├── example_json_converter.dart
└── example_permissions.dart             # only when needed
```

- Models are `@immutable` with final fields (or freezed). `copyWith` takes `ValueGetter<T?>?` for
  nullable fields so a value can be explicitly cleared (`description: () => null`).
- API parsing is a `Converter<Map<String, Object?>, Example>`. Keep snake_case API keys in
  converters and repositories, not in widgets.
- Parse backend numbers tolerantly: `double.tryParse('${json['amount']}')`,
  `int.tryParse('${json['id']}')`.
- No private `_exampleFromJson` helpers in widgets or repositories when the parsing belongs in
  `models/example_json_converter.dart`.

## Repositories

`abstract interface class IExampleRepository` plus `ExampleRepositoryImpl` that receives its
services (API client, database, ...) through the constructor and does the request and the
conversion itself. There is no `*_datasource.dart` layer.

App-global scope values (selected store, active organisation) are read by the repository on each
call (it takes `SharedPreferences` or the scope service in its constructor). Only per-screen query
parameters (filters, search terms, ids) travel through `load(...)` / `paginate(...)`.

## Local database tables

Add a Drift table only for offline drafts or local persistence. See skill `drift-migration`.

## Localization

All visible widget text is localized: add every key to every `.arb` file
(`lib/src/common/localization/intl_en.arb`, `intl_ru.arb`), use
`Localization.of(context).exampleKey`, reuse keys first, never hardcode text, never edit generated
localization files.

## Reusable widgets

A control used in more than one feature goes to `lib/src/common/widget/`. Keep feature-specific UI in
its feature folder; promote only genuinely reused controls. Reuse existing common widgets for
tables, filters, reset/cancel buttons, status pills, empty/error/loading states, image viewers and
shimmer placeholders.

## Widgets

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

## Steps for a new feature

1. Create `lib/src/feature/<feature>/{models,data,controller,widgets}` (only what is needed).
2. Model and converter, repository interface plus Impl, freezed states and controller.
3. Config widget (controllers in `initState`, disposed in `dispose`) and the screen widgets.
4. Register app-wide services in the dependency initialization (see skill `dependency-injection`).
5. Localize every visible string.
6. `dart run build_runner build --delete-conflicting-outputs && dart format lib/`
7. Unit-test the controller and repository with fakes.
