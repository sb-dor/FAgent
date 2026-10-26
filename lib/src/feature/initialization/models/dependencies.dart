import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/initialization/widget/dependencies_scope.dart';

/// {@template dependencies}
/// Application dependencies.
/// {@endtemplate}
class Dependencies {
  /// {@macro dependencies}
  Dependencies();

  /// The state from the closest instance of this class.
  ///
  /// {@macro dependencies}
  factory Dependencies.of(BuildContext context) => DependenciesScope.of(context);

  /// Injest dependencies to the widgets tree.
  Widget inject({required Widget child, Key? key}) =>
      DependenciesScope(dependencies: this, key: key, child: child);

  /// Database
  late final AppDatabase database;

  @override
  String toString() => 'Dependencies{}';
}
