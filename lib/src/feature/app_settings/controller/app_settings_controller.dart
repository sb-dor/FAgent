import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_settings_controller.freezed.dart';

@freezed
sealed class AppSettingsState with _$AppSettingsState {
  const factory AppSettingsState.initial() = AppSettings$InitialState;

  const factory AppSettingsState.inProgress() = AppSettings$InProgressState;

  const factory AppSettingsState.error({Object? error, required AppSettings settings}) =
      AppSettings$ErrorState;

  const factory AppSettingsState.completed({required AppSettings settings}) =
      AppSettings$CompletedState;
}

/// Keeps the window-level settings in sync with the database.
///
/// Sequential for changes too: a pane width stored while another change is in flight must not be lost.
final class AppSettingsController extends StateController<AppSettingsState>
    with SequentialControllerHandler {
  AppSettingsController({
    required this._repository,
    super.initialState = const AppSettingsState.initial(),
  });

  final IAppSettingsRepository _repository;
  StreamSubscription<AppSettings>? _subscription;

  /// The latest known settings, or the defaults before the first load.
  AppSettings get settings => switch (state) {
    AppSettings$ErrorState(:final settings) ||
    AppSettings$CompletedState(:final settings) => settings,
    _ => const AppSettings(),
  };

  /// Starts following the stored settings.
  void watch() => handle(
    () async {
      setState(const AppSettingsState.inProgress());
      await _subscription?.cancel();
      _subscription = _repository.watch().listen(
        (settings) => setState(AppSettingsState.completed(settings: settings)),
        onError: (Object error) =>
            setState(AppSettingsState.error(error: error, settings: settings)),
      );
    },
    error: (error, stackTrace) async =>
        setState(AppSettingsState.error(error: error, settings: settings)),
  );

  /// Stores the settings [change] returns for the current ones.
  void update(AppSettings Function(AppSettings current) change) => handle(
    () async {
      final next = change(settings);
      // Show the change right away; the stream confirms it.
      setState(AppSettingsState.completed(settings: next));
      await _repository.update(next);
    },
    error: (error, stackTrace) async =>
        setState(AppSettingsState.error(error: error, settings: settings)),
  );

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
