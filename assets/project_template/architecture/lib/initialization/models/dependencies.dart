import 'package:flutter/widgets.dart';
import 'package:l/l.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:{{package}}/_core/telemetry/telemetry_setup.dart';
import 'package:{{package}}/initialization/widget/dependencies_scope.dart';

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

  /// Key-value storage with a read cache.
  late final SharedPreferencesWithCache sharedPreferences;

  /// The error log, the queue and the sender of crash reports; `null` on the web and when
  /// `logs.sqlite` could not be opened (the app works on, errors go to the console).
  TelemetryRuntime? telemetryRuntime;

  /// What closes the error log, in order (the sender and `logs.sqlite`, then the crash reporter);
  /// filled by the "Error log" step.
  final List<Future<void> Function()> errorLogClosers = <Future<void> Function()>[];

  Future<void>? _errorLogClosed;

  /// Closes the error log: last in `$disposeApp`, and after a failed startup. The second call waits
  /// for the first and does nothing more.
  Future<void> closeErrorLog() => _errorLogClosed ??= () async {
    for (final close in errorLogClosers) {
      try {
        await close();
      } on Object catch (error, stackTrace) {
        // The log is closing: the console is all that is left.
        l.w('Closing the error log failed: $error', stackTrace);
      }
    }
  }();

  @override
  String toString() => 'Dependencies{}';
}
