import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:{{package}}/src/_core/controller/controller_observer.dart';
import 'package:{{package}}/src/_core/utils/error_util/error_util.dart';
import 'package:{{package}}/src/initialization/data/initialize_dependencies.dart';
import 'package:{{package}}/src/initialization/models/dependencies.dart';

/// Ephemerally initializes the app and prepares it for use.
Future<Dependencies>? _$initializeApp;

/// Initializes the app and prepares it for use.
Future<Dependencies> $initializeApp({
  void Function(int progress, String message)? onProgress,
  Future<void> Function(Dependencies dependencies)? onSuccess,
  void Function(Object error, StackTrace stackTrace)? onError,
}) => _$initializeApp ??= Future<Dependencies>(() async {
  late final WidgetsBinding binding;
  try {
    binding = WidgetsFlutterBinding.ensureInitialized()..deferFirstFrame();
    await _catchExceptions();
    // Logs every controller's handlers, state changes and errors (docs/rules/controllers.md).
    Controller.observer = const ControllerObserver();
    final dependencies = await $initializeDependencies(onProgress: onProgress)
        .timeout(const Duration(minutes: 1));
    await onSuccess?.call(dependencies);
    return dependencies;
  } on Object catch (error, stackTrace) {
    onError?.call(error, stackTrace);
    ErrorUtil.logError(error, stackTrace, hint: 'Failed to initialize app').ignore();
    rethrow;
  } finally {
    binding.addPostFrameCallback((_) {
      // Closes splash screen, and show the app layout.
      binding.allowFirstFrame();
    });
    _$initializeApp = null;
  }
});

/// Disposes the app and releases all resources.
@visibleForTesting
Future<void> $disposeApp(Dependencies dependencies) async {
  // Close what the dependencies own, in reverse order of creation.
}

/// Whether [_catchExceptions] already installed the handlers. A retried start runs it again, and a
/// second install would wrap the first handler and report every error twice.
bool _handlersInstalled = false;

Future<void> _catchExceptions() async {
  if (_handlersInstalled) return;
  _handlersInstalled = true;
  try {
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      ErrorUtil.logError(error, stackTrace, hint: 'ROOT ERROR\r\n${Error.safeToString(error)}').ignore();
      return true;
    };

    final sourceFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      // Errors the framework marks silent (a failed image load, for example) are expected in
      // production: a warning, not a crash.
      if (details.silent) {
        ErrorUtil.logMessage(
          details.exceptionAsString(),
          stackTrace: details.stack,
          hint: 'FLUTTER ERROR (silent)',
          warning: true,
        ).ignore();
        sourceFlutterError?.call(details);
        return;
      }
      ErrorUtil.logError(
        details.exception,
        details.stack ?? StackTrace.current,
        hint: 'FLUTTER ERROR\r\n$details',
      ).ignore();
      sourceFlutterError?.call(details);
    };
  } on Object catch (error, stackTrace) {
    ErrorUtil.logError(error, stackTrace).ignore();
  }
}
