import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/_core/utils/error_util.dart';
import 'package:flutter_code_agent/initialization/data/initialize_dependencies.dart';
import 'package:flutter_code_agent/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/initialization/models/initialization_exception.dart';
import 'package:l/l.dart';

/// Ephemerally initializes the app and prepares it for use.
Future<Dependencies>? _$initializeApp;

/// Initializes the app and prepares it for use.
Future<Dependencies> $initializeApp({
  void Function(int progress, String message)? onProgress,
  Future<void> Function(Dependencies dependencies)? onSuccess,
  void Function(Object error, StackTrace stackTrace)? onError,
  @visibleForTesting Map<String, InitializationStep>? steps,
}) => _$initializeApp ??= Future<Dependencies>(() async {
  // One deferral and one allowance per attempt, so a retry never allows a frame twice.
  final binding = WidgetsFlutterBinding.ensureInitialized()..deferFirstFrame();
  try {
    await _catchExceptions();
    final dependencies = await $initializeDependencies(
      onProgress: onProgress,
      // ignore: invalid_use_of_visible_for_testing_member, the steps of a test
      steps: steps,
    );
    await onSuccess?.call(dependencies);
    return dependencies;
  } on Object catch (error, stackTrace) {
    onError?.call(error, stackTrace);
    // A failed step is already reported (fatal) before its closers run; this is for the rest.
    if (error is! InitializationException) {
      ErrorUtil.logError(error, stackTrace, hint: 'STARTUP ERROR', fatal: true).ignore();
    }
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
  await dependencies.appRunRepository.dispose();
  await dependencies.devicesRepository.dispose();
  await dependencies.agentHub.dispose();
  await dependencies.database.close();
  // Last: the closing above may still report.
  await dependencies.closeErrorLog();
}

bool _handlersInstalled = false;

/// How many times the error handlers were installed; once per app run.
@visibleForTesting
int handlerInstalls = 0;

Future<void> _catchExceptions() async {
  if (_handlersInstalled) return;
  _handlersInstalled = true;
  handlerInstalls++;
  try {
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      ErrorUtil.logError(error, stackTrace, hint: 'ROOT ERROR').ignore();
      return true;
    };

    final sourceFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.silent) {
        // The framework marks these as not worth a report (a failed image, a layout notice).
        l.w('FLUTTER ERROR (silent) | ${details.exceptionAsString()}', details.stack);
      } else {
        ErrorUtil.logError(
          details.exception,
          details.stack ?? StackTrace.current,
          hint: 'FLUTTER ERROR',
        ).ignore();
      }
      sourceFlutterError?.call(details);
    };
  } on Object catch (error, stackTrace) {
    ErrorUtil.logError(error, stackTrace).ignore();
  }
}
