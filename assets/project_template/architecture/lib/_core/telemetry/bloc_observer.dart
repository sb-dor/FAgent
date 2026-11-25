import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:l/l.dart';
import 'package:{{package}}/_core/telemetry/error_util.dart';

/// Observer for every [Bloc]: its creation, events, transitions, errors and closing.
///
/// Every error a bloc reports (`addError`, or one that left a handler) goes to [ErrorUtil],
/// expected or not: it decides that an expected failure stays in the log and only a bug is queued
/// for the crash reporter (docs/rules/bloc.md, "Where the error goes").
final class AppBlocObserver extends BlocObserver {
  /// Creates the observer.
  const AppBlocObserver();

  @override
  void onCreate(BlocBase<Object?> bloc) {
    super.onCreate(bloc);
    l.v6('Bloc | ${bloc.runtimeType}.new');
  }

  @override
  void onEvent(Bloc<Object?, Object?> bloc, Object? event) {
    super.onEvent(bloc, event);
    l.d('Bloc | ${bloc.runtimeType} | ${event.runtimeType}');
  }

  @override
  void onTransition(Bloc<Object?, Object?> bloc, Transition<Object?, Object?> transition) {
    super.onTransition(bloc, transition);
    // Types only: a state may hold tokens and people's data, and the log goes into crash reports.
    l.v(
      '${bloc.runtimeType}: ${transition.currentState.runtimeType} -> '
      '${transition.nextState.runtimeType}',
    );
  }

  /// The error must not propagate out of the observer, so [ErrorUtil] logs it right here.
  @override
  void onError(BlocBase<Object?> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    unawaited(ErrorUtil.logError(error, stackTrace, hint: '${bloc.runtimeType} failed'));
  }

  @override
  void onClose(BlocBase<Object?> bloc) {
    super.onClose(bloc);
    l.v5('Bloc | ${bloc.runtimeType}.close');
  }
}
