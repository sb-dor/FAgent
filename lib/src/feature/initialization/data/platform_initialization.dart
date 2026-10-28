import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window setup. The app ships for desktop only.
Future<void> $platformInitialization() async {
  final platform = ui.PlatformDispatcher.instance;
  await windowManager.ensureInitialized();
  final windowOptions = WindowOptions(
    minimumSize: const Size(900, 600),
    size: const Size(1280, 800),
    center: true,
    windowButtonVisibility: true,
    backgroundColor: platform.platformBrightness == Brightness.dark
        ? AppColors.dark.bg
        : AppColors.light.bg,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Flutter Code Agent',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (io.Platform.isMacOS) {
      await windowManager.setMovable(true);
    }
    await windowManager.setMaximizable(true);
    await windowManager.show();
    await windowManager.focus();
  });
}
