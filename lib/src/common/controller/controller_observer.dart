import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/common/utils/error_util.dart';
import 'package:l/l.dart';

/// Observer for [Controller], react to changes in any controller.
///
/// Every error a controller did not catch goes to [ErrorUtil], expected or not: it decides that an
/// expected failure stays in the log and only a bug is queued for crash reports.
final class ControllerObserver implements IControllerObserver {
  /// Creates the observer.
  const ControllerObserver();

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
  void onStateChanged<S extends Object>(StateController<S> controller, S prevState, S nextState) =>
      // Types only: a state may hold paths, messages and tokens.
      l.v('${controller.name}: ${prevState.runtimeType} -> ${nextState.runtimeType}');

  /// The error must not propagate out of the observer, so [ErrorUtil] logs it right here.
  @override
  void onError(Controller controller, Object error, StackTrace stackTrace) =>
      unawaited(ErrorUtil.logError(error, stackTrace, hint: '${controller.name} failed'));
}
