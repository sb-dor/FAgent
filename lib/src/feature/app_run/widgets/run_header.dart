import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/flutter_daemon/flutter_exceptions.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_device_chip.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_reload_switch.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_status.dart';
import 'package:path/path.dart' as p;

/// What the buttons of the Run header ask for.
enum RunAction {
  /// Start the app.
  start,

  /// Stop the app.
  stop,

  /// Hot reload.
  reload,

  /// Hot restart.
  restart,

  /// Pick a widget in the running app.
  pick,

  /// Take a screenshot of the device.
  screenshot,

  /// Open DevTools.
  devTools,
}

/// {@template run_header}
/// The top of the Run tab: the device, mode and entry point chips, the action buttons, the status
/// line and the "reload after every agent turn" switch.
///
/// Where the device chip would be, the header says what is wrong with the devices instead: no
/// Flutter SDK (with a link to its settings), a failure to get them (with a retry), or that there
/// are none. While the chosen device is an emulator that is still booting, the status line says so
/// and Run waits.
/// {@endtemplate}
class RunHeader extends StatelessWidget {
  /// {@macro run_header}
  const RunHeader({
    required this.state,
    required this.devices,
    required this.isPreview,
    required this.onDevice,
    required this.onMode,
    required this.onAction,
    required this.onRetryDevices,
    required this.onOpenFlutterSettings,
    this.launchFailed = false,
    super.key,
  });

  /// What the tab shows for the project.
  final RunViewState state;

  /// The devices, or why there are none.
  final DevicesState devices;

  /// Whether the data is made up.
  final bool isPreview;

  /// Called with the id of the device the user chose.
  final ValueChanged<String> onDevice;

  /// Called with the build mode the user chose.
  final ValueChanged<BuildMode> onMode;

  /// Called when the user presses one of the buttons.
  final ValueChanged<RunAction> onAction;

  /// Called when the user asks to try getting the devices again.
  final VoidCallback onRetryDevices;

  /// Called when the user follows the link to the Flutter settings.
  final VoidCallback onOpenFlutterSettings;

  /// Whether booting the chosen emulator failed; the status line says so, with a retry.
  final bool launchFailed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final run = state.run;
    final active = run is RunBuilding || run is RunRunning;
    final deviceList = switch (devices) {
      Devices$CompletedState(:final devices) => devices,
      _ => const <Device>[],
    };
    final selected = deviceList.where((device) => device.id == state.selectedDeviceId).firstOrNull;
    final launching = selected?.kind == DeviceKind.available;
    final canStart = state.selectedDeviceId != null && !launching;

    Widget button(
      RunAction action,
      IconData icon,
      String tooltip, {
      bool enabled = true,
      bool primary = false,
      bool danger = false,
    }) => IconButton(
      onPressed: enabled ? () => onAction(action) : null,
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      style: IconButton.styleFrom(
        fixedSize: const Size(28, 26),
        minimumSize: const Size(28, 26),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
        backgroundColor: primary && enabled ? colors.accent : colors.bg,
        foregroundColor: primary
            ? colors.onAccent
            : danger
            ? colors.danger
            : colors.text,
        disabledForegroundColor: colors.muted.withValues(alpha: 0.5),
        side: BorderSide(color: primary && enabled ? colors.accent : colors.border),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                switch (devices) {
                  Devices$ErrorState(:final error) when error is FlutterNotFoundException =>
                    _DevicesProblem(
                      message: localization.flutterSdkNotFound,
                      action: localization.newProjectSdkSettings,
                      onAction: onOpenFlutterSettings,
                    ),
                  Devices$ErrorState() => _DevicesProblem(
                    message: localization.runDevicesFailed,
                    action: localization.retry,
                    onAction: onRetryDevices,
                  ),
                  Devices$CompletedState(:final devices) when devices.isEmpty => _DevicesProblem(
                    message: localization.runNoDevices,
                    muted: true,
                  ),
                  _ => RunDeviceChip(
                    devices: deviceList,
                    selectedDeviceId: state.selectedDeviceId,
                    onSelected: onDevice,
                  ),
                },
                SelectorChip<BuildMode>(
                  label: state.mode.name,
                  menuWidth: 160,
                  sections: <AppMenuSection<BuildMode>>[
                    AppMenuSection<BuildMode>(
                      items: <AppMenuItem<BuildMode>>[
                        for (final mode in BuildMode.values)
                          AppMenuItem<BuildMode>(
                            value: mode,
                            title: mode.name,
                            selected: mode == state.mode,
                          ),
                      ],
                    ),
                  ],
                  onSelected: onMode,
                ),
                Tooltip(
                  message: state.target,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      border: Border.all(color: colors.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: Text(
                        p.basename(state.target),
                        style: AppText.mono(context, size: 11).copyWith(height: 18 / 11),
                      ),
                    ),
                  ),
                ),
                if (isPreview) const PreviewBadge(),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                if (active)
                  button(RunAction.stop, Icons.stop, localization.runStop, danger: true)
                else
                  button(
                    RunAction.start,
                    Icons.play_arrow,
                    canStart
                        ? localization.runStart
                        : launching
                        ? (launchFailed
                              ? localization.runLaunchFailed
                              : localization.runLaunchingEmulator)
                        : localization.runChooseDeviceFirst,
                    enabled: canStart,
                    primary: true,
                  ),
                button(
                  RunAction.reload,
                  Icons.bolt,
                  localization.hotReload,
                  enabled: run is RunRunning,
                ),
                button(
                  RunAction.restart,
                  Icons.refresh,
                  localization.hotRestart,
                  enabled: run is RunRunning,
                ),
                button(
                  RunAction.pick,
                  Icons.ads_click,
                  localization.pickWidget,
                  enabled: run is RunRunning,
                ),
                button(RunAction.screenshot, Icons.photo_camera_outlined, localization.screenshot),
                button(RunAction.devTools, Icons.open_in_new, localization.devTools),
              ],
            ),
            const SizedBox(height: 8),
            if (launching && launchFailed)
              _DevicesProblem(
                message: localization.runLaunchFailed,
                action: localization.retry,
                onAction: () => onDevice(selected!.id),
              )
            else if (launching)
              Text(
                localization.runLaunchingEmulator,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11),
              )
            else
              RunStatus(run: run),
            const SizedBox(height: 4),
            const RunReloadSwitch(),
          ],
        ),
      ),
    );
  }
}

/// What is wrong with the devices, in the place of the device chip: [message] and, when there is
/// something to do about it, a link [action].
class _DevicesProblem extends StatelessWidget {
  const _DevicesProblem({required this.message, this.action, this.onAction, this.muted = false});

  final String message;
  final String? action;
  final VoidCallback? onAction;

  /// Whether this is only a hint (no devices) and not a failure.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(context).textTheme.bodySmall!;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(message, style: style.copyWith(color: muted ? colors.muted : colors.danger)),
        if (action != null)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.small),
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(action!, style: style.copyWith(color: colors.accent)),
            ),
          ),
      ],
    );
  }
}
