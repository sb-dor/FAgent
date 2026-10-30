import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_device_chip.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/app_title_bar.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template workspace_run_controls}
/// The run controls of the title bar: the device chip, Run (Stop while the app builds or runs) and
/// hot reload, and the Preview badge while the run is made up. Nothing is shown without a selected
/// project.
/// {@endtemplate}
class WorkspaceRunControls extends StatelessWidget {
  /// {@macro workspace_run_controls}
  const WorkspaceRunControls({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = WorkspaceConfigInhWidget.of(context);
    final localization = Localization.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        scope.dataController,
        scope.runController,
        scope.devicesController,
      ]),
      builder: (context, _) {
        if (scope.dataController.projectId == null) return const SizedBox.shrink();
        final link = scope.runLink;
        final devices = switch (scope.devicesController.state) {
          Devices$CompletedState(:final devices) => devices,
          _ => const <Device>[],
        };
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: RunDeviceChip(
                devices: devices,
                selectedDeviceId: scope.runController.state.selectedDeviceId,
                onSelected: (id) => scope.runController.choose(deviceId: id),
              ),
            ),
            const SizedBox(width: 6),
            if (link.isActive)
              TitleBarButton(
                icon: Icons.stop,
                tooltip: localization.runStop,
                color: context.colors.danger,
                onPressed: link.stop,
              )
            else
              Tooltip(
                message: link.canStart ? localization.runStart : localization.runChooseDeviceFirst,
                child: CompactButton(
                  primary: true,
                  icon: Icons.play_arrow,
                  label: localization.runStart,
                  onPressed: link.canStart ? link.start : null,
                ),
              ),
            const SizedBox(width: 2),
            TitleBarButton(
              icon: Icons.bolt,
              tooltip: localization.hotReload,
              onPressed: link.isRunning ? link.reload : null,
            ),
            if (scope.runIsPreview) ...<Widget>[const SizedBox(width: 6), const PreviewBadge()],
          ],
        );
      },
    );
  }
}
