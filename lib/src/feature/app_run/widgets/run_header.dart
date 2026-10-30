import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_state.dart';
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
    super.key,
  });

  /// What the tab shows for the project.
  final RunViewState state;

  /// The devices known right now.
  final List<Device> devices;

  /// Whether the data is made up.
  final bool isPreview;

  /// Called with the id of the device the user chose.
  final ValueChanged<String> onDevice;

  /// Called with the build mode the user chose.
  final ValueChanged<BuildMode> onMode;

  /// Called when the user presses one of the buttons.
  final ValueChanged<RunAction> onAction;

  static const String _argumentsValue = '';

  static IconData _platformIcon(DevicePlatform platform) => switch (platform) {
    DevicePlatform.ios => Icons.phone_iphone,
    DevicePlatform.android => Icons.phone_android,
    DevicePlatform.macos => Icons.desktop_mac_outlined,
    DevicePlatform.web => Icons.public,
    DevicePlatform.windows || DevicePlatform.linux => Icons.desktop_windows_outlined,
  };

  AppMenuItem<String> _item(Device device) => AppMenuItem<String>(
    value: device.id,
    title: device.name,
    subtitle: device.detail,
    icon: _platformIcon(device.platform),
    selected: device.id == state.selectedDeviceId,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final run = state.run;
    final selected = devices.where((device) => device.id == state.selectedDeviceId).firstOrNull;
    final running = devices.where((device) => device.kind == DeviceKind.running);
    final available = devices.where((device) => device.kind == DeviceKind.available);
    final active = run is RunBuilding || run is RunRunning;
    final canStart = state.selectedDeviceId != null;

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
            ? Theme.of(context).colorScheme.onPrimary
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
                SelectorChip<String>(
                  label: selected?.name ?? localization.chooseDevice,
                  icon: selected == null ? Icons.devices : _platformIcon(selected.platform),
                  menuWidth: 300,
                  sections: <AppMenuSection<String>>[
                    if (running.isNotEmpty)
                      AppMenuSection<String>(
                        title: localization.devicesRunning,
                        items: running.map(_item).toList(growable: false),
                      ),
                    if (available.isNotEmpty)
                      AppMenuSection<String>(
                        title: localization.devicesAvailable,
                        items: available.map(_item).toList(growable: false),
                      ),
                    if (devices.isNotEmpty)
                      AppMenuSection<String>(
                        items: <AppMenuItem<String>>[
                          AppMenuItem<String>(
                            value: _argumentsValue,
                            title: localization.runArguments,
                            subtitle: localization.comingInMilestone('M2'),
                            icon: Icons.tune,
                            enabled: false,
                          ),
                        ],
                      ),
                  ],
                  onSelected: onDevice,
                ),
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
                    canStart ? localization.runStart : localization.runChooseDeviceFirst,
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
            RunStatus(run: run),
            const SizedBox(height: 4),
            const RunReloadSwitch(),
          ],
        ),
      ),
    );
  }
}
