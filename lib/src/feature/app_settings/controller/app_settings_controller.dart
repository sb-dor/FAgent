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
/// Every change is built on the latest *intended* settings, never on the defaults shown before the
/// stored row is loaded and never on a database echo of an earlier write.
final class AppSettingsController extends StateController<AppSettingsState>
    with SequentialControllerHandler {
  AppSettingsController({
    required this._repository,
    super.initialState = const AppSettingsState.initial(),
  });

  final IAppSettingsRepository _repository;
  StreamSubscription<AppSettings>? _subscription;
  final Completer<void> _firstLoad = Completer<void>();

  /// The settings as of the last accepted database emission, or the last successful write.
  AppSettings? _confirmed;

  /// What the user last asked for; the base of the next change.
  AppSettings? _intended;

  /// Updates called but not yet written.
  int _pendingWrites = 0;

  /// A write finished and its echo has not arrived yet: older emissions are stale.
  bool _awaitingEcho = false;

  /// The latest known settings, or the defaults before the first load.
  AppSettings get settings => switch (state) {
    AppSettings$ErrorState(:final settings) ||
    AppSettings$CompletedState(:final settings) => settings,
    _ => const AppSettings(),
  };

  /// Starts following the stored settings.
  void watch() => handle(() async {
    setState(const AppSettingsState.inProgress());
    _listen();
  }, error: (error, stackTrace) async => _fail(error));

  void _listen() {
    _subscription?.cancel().ignore();
    _subscription = _repository.watch().listen(_onStored, onError: _fail);
  }

  void _onStored(AppSettings stored) {
    if (!_firstLoad.isCompleted) {
      _confirmed = _intended = stored;
      setState(AppSettingsState.completed(settings: stored));
      _firstLoad.complete();
      return;
    }
    // Our own writes are still in flight (or their echo is): this emission may predate them.
    if (_pendingWrites > 0) return;
    if (_awaitingEcho) {
      if (stored != _intended) return;
      _awaitingEcho = false;
    }
    _confirmed = _intended = stored;
    setState(AppSettingsState.completed(settings: stored));
  }

  void _fail(Object error) {
    if (!_firstLoad.isCompleted) _firstLoad.complete();
    setState(AppSettingsState.error(error: error, settings: _intended ?? settings));
  }

  /// Stores the settings [change] returns for the latest intended ones.
  ///
  /// Waits for the stored row to load first, so a change never builds on (and writes) the defaults.
  void update(AppSettings Function(AppSettings current) change) {
    _pendingWrites++;
    handle(() async {
      try {
        if (_subscription == null) _listen();
        await _firstLoad.future;
        final base = _intended;
        if (base == null) throw StateError('The stored settings could not be loaded');
        final next = change(base);
        _intended = next;
        setState(AppSettingsState.completed(settings: next));
        await _repository.update(next);
        _confirmed = next;
        _awaitingEcho = true;
      } on Object {
        _intended = _confirmed;
        rethrow;
      } finally {
        _pendingWrites--;
      }
    }, error: (error, stackTrace) async => _fail(error));
  }

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
