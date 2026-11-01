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
