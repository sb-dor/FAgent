---
name: dependency-injection
description: "Global Dependencies with DependenciesScope, feature config widgets with InheritedWidget scopes, interface-based constructor injection."
when_to_use: "When adding an app-wide service, wiring a feature's controllers, or deciding how a widget gets a dependency."
version: "2.0"
---

# Dependency injection

## Global: `Dependencies` and `DependenciesScope`

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

## Feature level: config widgets

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
  if (_authenticationController.state is Authentication$AuthenticatedState && isLoading) {
    // initialize the controllers for the authenticated state
  }
}
```

## Reaching feature dependencies

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

## Interfaces and constructor injection

- Repositories are interfaces with an implementation: `abstract interface class IExampleRepository`,
  `IProductsRepository`, and so on. Controller interfaces when applicable.
- Dependencies come through constructors:

```dart
// A repository implementation receives its services.
ExampleRepositoryImpl({required final ApiClient apiClient}) : _apiClient = apiClient;

// A controller receives the repository interface.
ExampleController({required final IExampleRepository exampleRepository, /* ... */})
```

- Widgets get app-wide services from `DependenciesScope` and feature controllers from the feature
  scope. A widget never builds a repository itself and never holds one (see skill
  `feature-architecture`).
- Never create a dependency inside a controller: it cannot be replaced in a test.
