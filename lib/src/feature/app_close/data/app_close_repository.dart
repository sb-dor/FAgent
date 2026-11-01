import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/app_mcp/app_mcp_server.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_settings/data/app_settings_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_probe.dart';
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

  /// Stops the runs, the devices daemon, the agents, the app's MCP server and the MCP status probes,
  /// then closes the database.
  Future<void> shutdown();

  /// Quits the app (answering a pending ⌘Q or logout on macOS).
  Future<void> quit();

  /// Keeps the app open, declining a pending ⌘Q or logout.
  Future<void> cancelQuit();
}

/// window_manager-backed [IAppCloseRepository].
final class AppCloseRepositoryImpl implements IAppCloseRepository {
  /// Creates the repository.
  AppCloseRepositoryImpl({
    required this._hub,
    required this._database,
    required this._settings,
    required this._appRun,
    required this._devices,
    required this._appMcpServer,
    required this._mcpProbe,
  });

  final AgentHub _hub;
  final AppDatabase _database;
  final IAppSettingsRepository _settings;
  final IAppRunRepository _appRun;
  final IDevicesRepository _devices;
  final IAppMcpServer _appMcpServer;
  final IMcpProbe _mcpProbe;

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
    // `flutter run` and `flutter daemon` live in their own process groups, so they outlive the app
    // unless they are killed here (the app on the device closes with them). One that refuses to
    // stop must not keep the agents running or the database open.
    await Future.wait<void>(<Future<void>>[
      _stopQuietly('runs', _appRun.dispose),
      _stopQuietly('devices', _devices.dispose),
    ]);
    await _hub.dispose();
    // After the agents, so none of them is cut off mid-call; before the database its tools read.
    await _stopQuietly('app MCP server', _appMcpServer.close);
    // The status probes of Settings run user servers (`npx` and the like) in their own process
    // groups, which would outlive the app.
    await _stopQuietly('MCP probes', _mcpProbe.dispose);
    await _database.close();
  }

  Future<void> _stopQuietly(String what, Future<void> Function() dispose) async {
    try {
      await dispose();
    } on Object catch (error, stackTrace) {
      l.w('App close | stopping the $what failed: $error', stackTrace);
    }
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
