import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';

/// {@template inherited_dependencies}
/// InheritedDependencies widgets.
/// {@endtemplate}
class DependenciesScope extends InheritedWidget {
  /// {@macro inherited_dependencies}
  const DependenciesScope({required this.dependencies, required super.child, super.key});

  final Dependencies dependencies;

  /// The state from the closest instance of this class
  /// that encloses the given context, if any.
  static Dependencies? maybeOf(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<DependenciesScope>()?.widget
              as DependenciesScope?)
          ?.dependencies;

  static Never _notFoundInheritedWidgetOfExactType() => throw ArgumentError(
    'Out of scope, not found inherited widgets '
        'a InheritedDependencies of the exact type',
    'out_of_scope',
  );

  /// The state from the closest instance of this class
  /// that encloses the given context.
  static Dependencies of(BuildContext context) =>
      maybeOf(context) ?? _notFoundInheritedWidgetOfExactType();

  @override
  bool updateShouldNotify(covariant DependenciesScope oldWidget) => false;
}
