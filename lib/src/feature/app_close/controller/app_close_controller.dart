import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/app_close/data/app_close_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:l/l.dart';

part 'app_close_controller.freezed.dart';

@freezed
sealed class AppCloseState with _$AppCloseState {
  /// The app runs.
  const factory AppCloseState.initial() = AppClose$InitialState;

  /// [files] files of the Code view are unsaved: the user saves them, drops them or stays;
  /// [saveFailed] after a save that left some of them unsaved.
  const factory AppCloseState.unsaved({required int files, @Default(false) bool saveFailed}) =
      AppClose$UnsavedState;

  /// Agents work in [busyChats] chats: the user decides whether to quit.
  const factory AppCloseState.confirming({required int busyChats}) = AppClose$ConfirmingState;

  /// Agents are being stopped; the window closes next.
  const factory AppCloseState.inProgress() = AppClose$InProgressState;
}

/// Quits right away when nothing runs, otherwise asks first. Quitting stops
/// the agents (their turns are cancelled) before the window closes.
/// Sequential, not Droppable: a close request must not swallow the user's
/// answer to the dialog; each step re-checks the state instead.
final class AppCloseController extends StateController<AppCloseState>
    with SequentialControllerHandler {
  AppCloseController({
    required this._repository,
    super.initialState = const AppCloseState.initial(),
  });

  final IAppCloseRepository _repository;

  /// Longest wait for the agents to stop before quitting anyway.
  static const Duration shutdownTimeout = Duration(seconds: 30);
  StreamSubscription<void>? _requests;

  /// Starts intercepting window close requests.
  void watch() => handle(() async {
    await _requests?.cancel();
    _requests = _repository.closeRequests().listen((_) => requestClose());
  });

  /// The user asked to close the window: unsaved files ask first (whatever the setting), then
  /// working agents.
  void requestClose() => handle(() async {
    if (state is! AppClose$InitialState) return;
    final unsaved = _repository.unsavedFiles();
    if (unsaved > 0) {
      setState(AppCloseState.unsaved(files: unsaved));
      return;
    }
    await _checkAgents();
  });

  /// Saves the unsaved files, then goes on quitting; a save that leaves some unsaved asks again.
  void saveAndQuit() => handle(() async {
    if (state is! AppClose$UnsavedState) return;
    bool saved;
    try {
      saved = await _repository.saveAllFiles();
    } on Object catch (error, stackTrace) {
      // Not a refusal the files know about; the dialog must come back, or no quit would work.
      l.w('App close | saving the files failed: $error', stackTrace);
      saved = false;
    }
    if (!saved) {
      setState(AppCloseState.unsaved(files: _repository.unsavedFiles(), saveFailed: true));
      return;
    }
    await _checkAgents();
  });

  /// Goes on quitting without saving the unsaved files.
  void quitWithoutSaving() => handle(() async {
    if (state is AppClose$UnsavedState) await _checkAgents();
  });

  Future<void> _checkAgents() async {
    final busyChats = await _repository.busyChats();
    if (busyChats > 0 && await _repository.askBeforeQuit()) {
      setState(AppCloseState.confirming(busyChats: busyChats));
    } else {
      await _quit();
    }
  }

  /// Quits although agents work.
  void confirm() => handle(() async {
    if (state is AppClose$ConfirmingState) await _quit();
  });

  /// Keeps the app open.
  void cancel() => handle(() async {
    if (state is! AppClose$ConfirmingState && state is! AppClose$UnsavedState) return;
    setState(const AppCloseState.initial());
    await _repository.cancelQuit();
  });

  Future<void> _quit() async {
    setState(const AppCloseState.inProgress());
    try {
      await _repository.shutdown().timeout(shutdownTimeout);
    } on Object catch (error, stackTrace) {
      // Quit anyway rather than hang behind the barrier.
      l.w('App close | shutdown failed: $error', stackTrace);
    }
    await _repository.quit();
  }

  @override
  void dispose() {
    _requests?.cancel().ignore();
    super.dispose();
  }
}
