import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:l/l.dart';
import 'package:window_manager/window_manager.dart';

/// Closing the app while agents work.
abstract interface class IAppCloseRepository {
  /// Close requests of the window (close button, ⌘Q). While listened to, the
  /// window does not close by itself; cancelling the subscription restores
  /// that.
  Stream<void> closeRequests();

  /// Chats with a turn or setup in flight, plus a running login.
  Future<int> busyChats();

  /// Whether quitting while agents work asks the user first (a setting).
  Future<bool> askBeforeQuit();

  /// Stops the agents and closes the database.
  Future<void> shutdown();

  /// Quits the app (answering a pending ⌘Q or logout on macOS).
  Future<void> quit();

  /// Keeps the app open, declining a pending ⌘Q or logout.
  Future<void> cancelQuit();
}

/// window_manager-backed [IAppCloseRepository].
final class AppCloseRepositoryImpl implements IAppCloseRepository {
  /// Creates the repository.
  AppCloseRepositoryImpl({required this._hub, required this._database, required this._settings});

  final AgentHub _hub;
  final AppDatabase _database;
  final IAppSettingsRepository _settings;

  /// macOS: `AppDelegate` waits for the answer to a quit request.
  static const MethodChannel _channel = MethodChannel('flutter_code_agent/app_close');

  @override
  Stream<void> closeRequests() {
    final controller = StreamController<void>();
    final listener = _CloseListener(() {
      if (!controller.isClosed) controller.add(null);
    });
    controller
      ..onListen = () {
        windowManager.addListener(listener);
        windowManager.setPreventClose(true).ignore();
      }
      ..onCancel = () async {
        windowManager.removeListener(listener);
        await windowManager.setPreventClose(false);
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }

  @override
  Future<int> busyChats() async =>
      (await _hub.busySessions()).length + (_hub.auth.isRunning ? 1 : 0);

  @override
  Future<bool> askBeforeQuit() async => (await _settings.watch().first).askBeforeQuit;

  @override
  Future<void> shutdown() async {
    await _hub.dispose();
    await _database.close();
  }

  @override
  Future<void> quit() async {
    try {
      if (io.Platform.isMacOS) {
        await _channel.invokeMethod<void>('quit');
      } else {
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      }
    } on Object catch (error, stackTrace) {
      // Never leave the user with a window that cannot close.
      l.w('App close | quitting through the window failed: $error', stackTrace);
      io.exit(0);
    }
  }

  @override
  Future<void> cancelQuit() async {
    if (!io.Platform.isMacOS) return;
    await _channel.invokeMethod<void>('cancelQuit');
  }
}

class _CloseListener with WindowListener {
  _CloseListener(this._onClose);

  final void Function() _onClose;

  @override
  void onWindowClose() => _onClose();
}
