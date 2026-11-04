import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_config_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/log_entry.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/picked_widget_card.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_arguments_dialog.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_header.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_logs.dart';

/// {@template run_tab}
/// The Run tab of the right pane for [projectId]: device, mode and buttons on top, the widget
/// picker, and the logs.
///
/// The controllers belong to the window; the tab only shows them and asks them to act. The owner
/// calls [RunController.watch] for the selected project. The device to run on is chosen by the window
/// (first running one) or by the user in the device menu.
/// {@endtemplate}
class RunTab extends StatefulWidget {
  /// {@macro run_tab}
  const RunTab({
    required this.projectId,
    required this.projectRoot,
    required this.isPreview,
    required this.devices,
    required this.run,
    required this.actions,
    required this.runConfig,
    required this.onSendError,
    required this.onAddWidget,
    required this.onOpenFile,
    required this.onOpenFlutterSettings,
    super.key,
  });

  /// The selected project; `null` shows an empty state.
  final int? projectId;

  /// The folder of the selected project, which the screenshot of a picked widget is relative to;
  /// `null` when it is not known.
  final String? projectRoot;

  /// Whether the run data is made up.
  final bool isPreview;

  /// The devices that can run the app.
  final DevicesController devices;

  /// The run and the logs of the project.
  final RunController run;

  /// The actions (start, stop, reload) and the widget picker.
  final RunActionsController actions;

  /// Saves the run arguments the user edits in the dialog the device menu opens.
  final RunConfigController runConfig;

  /// Called with the log line when the user sends its error to the agent.
  final ValueChanged<LogEntry> onSendError;

  /// Called when the user adds the picked widget to the message.
  final ValueChanged<PickedWidget> onAddWidget;

  /// Called with a file (as the run reports it) and a line when the user opens a file.
  final void Function(String path, int? line) onOpenFile;

  /// Called when the user follows the link to the Flutter settings (shown when there is no SDK).
  final VoidCallback onOpenFlutterSettings;

  @override
  State<RunTab> createState() => _RunTabState();
}

class _RunTabState extends State<RunTab> {
  /// Chooses the device; an emulator that is not running yet is booted.
  void _chooseDevice(String id) {
    widget.run.choose(deviceId: id);
    widget.devices.launch(id);
  }

  void _editArguments() {
    final projectId = widget.projectId;
    if (projectId == null) return;
    RunArgumentsDialog.show(
      context,
      projectId: projectId,
      arguments: widget.run.state.arguments,
      controller: widget.runConfig,
    );
  }

  void _onRunAction(RunAction action) {
    final projectId = widget.projectId;
    final state = widget.run.state;
    if (projectId == null) return;
    switch (action) {
      case RunAction.start:
        final devices = switch (widget.devices.state) {
          Devices$CompletedState(:final devices) => devices,
          _ => const <Device>[],
        };
        final device = devices.where((device) => device.id == state.selectedDeviceId).firstOrNull;
        if (device != null && device.kind == DeviceKind.running) {
          widget.actions.start(
            projectId,
            device: device,
            mode: state.mode,
            arguments: () => widget.run.startArgumentsFor(projectId),
          );
        }
      case RunAction.stop:
        widget.actions.stop(projectId);
      case RunAction.reload:
        widget.actions.hotReload(projectId);
      case RunAction.restart:
        widget.actions.hotRestart(projectId);
      case RunAction.pick:
        widget.actions.pickWidget(projectId);
      case RunAction.screenshot:
        widget.actions.screenshot(projectId);
      case RunAction.devTools:
        widget.actions.openDevTools(projectId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    if (widget.projectId == null) {
      return EmptyState(
        icon: Icons.play_circle_outline,
        title: localization.runNoProject,
        message: localization.runNoProjectHint,
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.run, widget.devices, widget.actions.pick]),
      builder: (context, _) {
        final state = widget.run.state;
        final projectId = widget.projectId!;
        final pick = widget.actions.pick.value;
        final showsPick =
            pick.projectId == projectId &&
            (pick.picking || pick.widget != null || pick.problem != null);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RunHeader(
              state: state,
              devices: widget.devices.state,
              isPreview: widget.isPreview,
              onDevice: _chooseDevice,
              onEditArguments: _editArguments,
              onRetryDevices: widget.devices.watch,
              onOpenFlutterSettings: widget.onOpenFlutterSettings,
              launchFailed:
                  state.selectedDeviceId != null &&
                  widget.devices.launchFailed(state.selectedDeviceId!),
              onMode: (mode) => widget.run.choose(mode: mode),
              onAction: _onRunAction,
            ),
            if (showsPick)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: PickedWidgetCard(
                  pick: pick,
                  projectRoot: widget.projectRoot,
                  onCancel: () => widget.actions.cancelPick(projectId),
                  onSelect: (id) => widget.actions.selectAncestor(projectId, id),
                  onAddToMessage: widget.onAddWidget,
                  onOpenFile: widget.onOpenFile,
                ),
              ),
            Expanded(
              child: RunLogs(
                logs: state.logs,
                errorCount: state.errorCount,
                onClear: widget.run.clearLogs,
                onSend: widget.onSendError,
                onOpenFile: widget.onOpenFile,
              ),
            ),
          ],
        );
      },
    );
  }
}
