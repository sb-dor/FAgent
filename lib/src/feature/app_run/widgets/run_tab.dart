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
/// The Run tab of the right pane for [projectId]: device, mode and buttons on top, the picked
/// widget, and the logs.
///
/// The controllers belong to the window; the tab only shows them and asks them to act. The owner
/// calls [RunController.watch] for the selected project. The device to run on is chosen by the window
/// (first running one) or by the user in the device menu.
/// {@endtemplate}
class RunTab extends StatefulWidget {
  /// {@macro run_tab}
  const RunTab({
    required this.projectId,
    required this.isPreview,
    required this.pickerIsPreview,
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

  /// Whether the run data is made up.
  final bool isPreview;

  /// Whether the widget picker is made up. Next to a real run it is not offered: the button says
  /// the picker comes in M6, because a made-up widget would not be in the app.
  final bool pickerIsPreview;

  /// The devices that can run the app.
  final DevicesController devices;

  /// The run and the logs of the project.
  final RunController run;

  /// The actions (start, stop, reload, pick a widget).
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
  /// Whether the app waits for the user to tap a widget.
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    widget.actions.addListener(_onAction);
  }

  @override
  void dispose() {
    widget.actions.removeListener(_onAction);
    super.dispose();
  }

  void _onAction() {
    final state = widget.actions.state;
    if (_picking && (state is RunActions$CompletedState || state is RunActions$ErrorState)) {
      setState(() => _picking = false);
    }
  }

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

  void _comingIn(String milestone) {
    final message = Localization.of(context).comingInMilestone(milestone);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
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
            target: state.target,
            arguments: state.arguments,
          );
        }
      case RunAction.stop:
        widget.actions.stop(projectId);
      case RunAction.reload:
        widget.actions.hotReload(projectId);
      case RunAction.restart:
        widget.actions.hotRestart(projectId);
      case RunAction.pick:
        if (widget.pickerIsPreview && !widget.isPreview) {
          _comingIn('M6');
          return;
        }
        setState(() => _picking = true);
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
      listenable: Listenable.merge(<Listenable>[widget.run, widget.devices]),
      builder: (context, _) {
        final state = widget.run.state;
        final picked = state.picked;
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
            if (_picking || picked != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: PickedWidgetCard(
                  picked: _picking ? null : picked,
                  onAddToMessage: () => widget.onAddWidget(picked!),
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
