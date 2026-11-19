import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:flutter_code_agent/src/common/utils/expected_exception.dart';
import 'package:l/l.dart';

/// Observer for [Controller], react to changes in any controller.
final class ControllerObserver implements IControllerObserver {
  /// Creates the observer; [report] is where a bug goes, [ErrorUtil.logError] unless a test
  /// replaces it.
  const ControllerObserver({@visibleForTesting this.report});

  /// Receives every error that is not an [ExpectedException].
  final void Function(Object error, StackTrace stackTrace)? report;

  @override
  void onCreate(Controller controller) {
    l.v6('Controller | ${controller.name}.new');
  }

  @override
  void onDispose(Controller controller) {
    l.v5('Controller | ${controller.name}.dispose');
  }

  @override
  void onHandler(HandlerContext context) {
    final stopwatch = Stopwatch()..start();
    l.d('Controller | ${context.controller.name}.${context.name}', context.meta);
    context.done.whenComplete(() {
      stopwatch.stop();
      l.d(
        'Controller | ${context.controller.name}.${context.name} | '
        'duration: ${stopwatch.elapsed}',
        context.meta,
      );
    });
  }

  @override
  void onStateChanged<S extends Object>(StateController<S> controller, S prevState, S nextState) {
    final context = Controller.context;
    if (context == null) {
      // State change occurred outside of the handler
      l.d('StateController | ${controller.name} | $prevState -> $nextState');
    } else {
      // State change occurred inside the handler
      l.d(
        'StateController | ${controller.name}.${context.name} | $prevState -> $nextState',
        context.meta,
      );
    }
  }

  /// error should not be propagated from this [observer] to the outside
  /// So the [ErrorUtil] logs the error directly from this [observer]
  @override
  void onError(Controller controller, Object error, StackTrace stackTrace) {
    final context = Controller.context;
    if (error is ExpectedException) {
      // The user or the outside world caused it and the UI shows it: not a crash.
      l.i('Controller | ${controller.name}${context == null ? '' : '.${context.name}'} | $error');
      return;
    }
    if (context == null) {
      // Error occurred outside of the handler
      l.w('Controller | ${controller.name} | $error', stackTrace);
    } else {
      // Error occurred inside the handler
      l.w('Controller | ${controller.name}.${context.name} | $error', stackTrace, context.meta);
    }
    (report ?? ErrorUtil.logError)(error, stackTrace);
  }
}
