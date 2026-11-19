import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:flutter_code_agent/src/feature/initialization/data/initialize_dependencies.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';

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
  await dependencies.appRunRepository.dispose();
  await dependencies.devicesRepository.dispose();
  await dependencies.agentHub.dispose();
  await dependencies.database.close();
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
      ErrorUtil.logError(
        error,
        stackTrace,
        hint: 'ROOT ERROR\r\n${Error.safeToString(error)}',
      ).ignore();
      return true;
    };

    final sourceFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
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
