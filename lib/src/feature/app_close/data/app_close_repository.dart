import 'dart:async';

import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:window_manager/window_manager.dart';

/// Closing the app while agents work.
abstract interface class IAppCloseRepository {
  /// Close requests of the window (close button, ⌘Q). While listened to, the
  /// window does not close by itself; cancelling the subscription restores
  /// that.
  Stream<void> closeRequests();

  /// Chats with a turn or setup in flight, plus a running login.
  Future<int> busyChats();

  /// Stops the agents and closes the database.
  Future<void> shutdown();

  /// Closes the window, which quits the app.
  Future<void> closeWindow();
}

/// window_manager-backed [IAppCloseRepository].
final class AppCloseRepositoryImpl implements IAppCloseRepository {
  /// Creates the repository.
  AppCloseRepositoryImpl({required this._hub, required this._database});

  final AgentHub _hub;
  final AppDatabase _database;

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
  Future<void> shutdown() async {
    await _hub.dispose();
    await _database.close();
  }

  @override
  Future<void> closeWindow() async {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}

class _CloseListener with WindowListener {
  _CloseListener(this._onClose);

  final void Function() _onClose;

  @override
  void onWindowClose() => _onClose();
}
