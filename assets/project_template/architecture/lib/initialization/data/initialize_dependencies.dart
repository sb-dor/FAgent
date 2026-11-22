import 'dart:async';

import 'package:l/l.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:{{package}}/_core/constant/config.dart';
import 'package:{{package}}/_core/telemetry/error_util.dart';
import 'package:{{package}}/_core/telemetry/expected_failure.dart';
import 'package:{{package}}/_core/telemetry/telemetry_setup.dart';
import 'package:{{package}}/initialization/models/dependencies.dart';

/// Initializes the app and returns a [Dependencies] object.
///
/// When a step fails, the error is reported (fatal) while the error log is still open, the log is
/// closed, and an [InitializationException] is thrown.
Future<Dependencies> $initializeDependencies({
  void Function(int progress, String message)? onProgress,
}) async {
  final dependencies = Dependencies();
  final totalSteps = _initializationSteps.length;
  var currentStep = 0;
  for (final step in _initializationSteps.entries) {
    final stopwatch = Stopwatch()..start();
    try {
      currentStep++;
      final percent = (currentStep * 100 ~/ totalSteps).clamp(0, 100);
      onProgress?.call(percent, step.key);
      l.v6('Initialization | $currentStep/$totalSteps ($percent%) | "${step.key}"');
      await step.value(dependencies);
      l.v6('Initialization | "${step.key}" took ${stopwatch.elapsedMilliseconds} ms');
    } on Object catch (error, stackTrace) {
      // Before the log closes: a report after that is lost.
      await ErrorUtil.logError(error, stackTrace, hint: 'STARTUP ERROR', fatal: true);
      await ErrorUtil.settled();
      // Close what the finished steps opened, the error log last.
      await dependencies.closeErrorLog();
      Error.throwWithStackTrace(InitializationException(step.key, error), stackTrace);
    }
  }
  return dependencies;
}

/// A startup step failed; [$initializeDependencies] has already reported it.
final class InitializationException implements Exception {
  /// Creates the exception for the [step] that failed with [error].
  const InitializationException(this.step, this.error);

  /// The name of the step.
  final String step;

  /// What the step threw.
  final Object error;

  @override
  String toString() => 'Initialization failed at step "$step": $error';
}

typedef _InitializationStep = FutureOr<void> Function(Dependencies dependencies);

final Map<String, _InitializationStep> _initializationSteps = <String, _InitializationStep>{
  // First, so every later step and its failure is in the log (docs/rules/dependencies.md, "The
  // error log and the reporter").
  'Error log': (dependencies) async => dependencies.telemetryRuntime = await startTelemetryLog(
    appVersion: Config.appVersion,
    isExpected: isExpectedFailure,
    projectPackages: projectPackages,
    defer: (name, step) => dependencies.errorLogClosers.add(step),
  ),
  'Open shared preferences': (dependencies) async =>
      dependencies.sharedPreferences = await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      ),
};
