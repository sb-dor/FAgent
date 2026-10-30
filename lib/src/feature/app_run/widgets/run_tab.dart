import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/empty_state.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/devices_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_actions_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/controller/run_controller.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/device.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/picked_widget.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_error.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/picked_widget_card.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_header.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_logs.dart';

/// {@template run_tab}
/// The Run tab of the right pane for [projectId]: device, mode and buttons on top, the picked
/// widget, and the logs.
///
/// The controllers belong to the window; the tab only shows them and asks them to act. The owner
/// calls [RunController.watch] for the selected project. The first running device is chosen when
/// none is, so ▶ works right away.
/// {@endtemplate}
class RunTab extends StatefulWidget {
  /// {@macro run_tab}
  const RunTab({
    required this.projectId,
    required this.isPreview,
    required this.devices,
    required this.run,
    required this.actions,
    required this.onSendError,
    required this.onAddWidget,
    required this.onOpenFile,
    super.key,
  });

  /// The selected project; `null` shows an empty state.
  final int? projectId;

  /// Whether the run data is made up.
  final bool isPreview;

  /// The devices that can run the app.
  final DevicesController devices;

  /// The run and the logs of the project.
  final RunController run;

  /// The actions (start, stop, reload, pick a widget).
  final RunActionsController actions;

  /// Called when the user sends an error of the run to the agent.
  final ValueChanged<RunError> onSendError;

  /// Called when the user adds the picked widget to the message.
  final ValueChanged<PickedWidget> onAddWidget;

  /// Called with a file (as the run reports it) and a line when the user opens a file.
  final void Function(String path, int? line) onOpenFile;

  @override
  State<RunTab> createState() => _RunTabState();
}

class _RunTabState extends State<RunTab> {
  /// Whether the app waits for the user to tap a widget.
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    widget.devices.addListener(_chooseDefaultDevice);
    widget.run.addListener(_chooseDefaultDevice);
    widget.actions.addListener(_onAction);
    // Not during the build that mounts the tab: the listeners of the controllers rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) => _chooseDefaultDevice());
  }

  @override
  void dispose() {
    widget.devices.removeListener(_chooseDefaultDevice);
    widget.run.removeListener(_chooseDefaultDevice);
    widget.actions.removeListener(_onAction);
    super.dispose();
  }

  List<Device> get _devices => switch (widget.devices.state) {
    Devices$CompletedState(:final devices) => devices,
    _ => const <Device>[],
  };

  void _chooseDefaultDevice() {
    if (!mounted || widget.run.state.projectId == null) return;
    if (widget.run.state.selectedDeviceId != null) return;
    final first = _devices.where((device) => device.kind == DeviceKind.running).firstOrNull;
    if (first != null) widget.run.choose(deviceId: first.id);
  }

  void _onAction() {
    final state = widget.actions.state;
    if (_picking && (state is RunActions$CompletedState || state is RunActions$ErrorState)) {
      setState(() => _picking = false);
    }
  }

  void _comingInM2() {
    final message = Localization.of(context).comingInMilestone('M2');
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _onRunAction(RunAction action) {
    final projectId = widget.projectId;
    final state = widget.run.state;
    if (projectId == null) return;
    switch (action) {
      case RunAction.start:
        final deviceId = state.selectedDeviceId;
        if (deviceId != null) {
          widget.actions.start(
            projectId,
            deviceId: deviceId,
            mode: state.mode,
            target: state.target,
          );
        }
      case RunAction.stop:
        widget.actions.stop(projectId);
      case RunAction.reload:
        widget.actions.hotReload(projectId);
      case RunAction.restart:
        widget.actions.hotRestart(projectId);
      case RunAction.pick:
        setState(() => _picking = true);
        widget.actions.pickWidget(projectId);
      case RunAction.screenshot || RunAction.devTools:
        _comingInM2();
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
              devices: _devices,
              isPreview: widget.isPreview,
              onDevice: (id) => widget.run.choose(deviceId: id),
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
                onSend: (entry) => widget.onSendError(entry.error!),
                onOpenFile: widget.onOpenFile,
              ),
            ),
          ],
        );
      },
    );
  }
}
