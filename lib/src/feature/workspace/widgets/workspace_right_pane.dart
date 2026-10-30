import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/pane_tabs.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/run_tab.dart';
import 'package:flutter_code_agent/src/feature/app_settings/models/app_settings.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/controller/changed_files_notifier.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/models/changed_file.dart';
import 'package:flutter_code_agent/src/feature/changes_pane/widgets/changes_tab.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_handle.dart';
import 'package:flutter_code_agent/src/feature/chat/models/chat_item.dart';
import 'package:flutter_code_agent/src/feature/plan_pane/widgets/plan_tab.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// {@template workspace_right_pane}
/// The right pane: Changes, Run and Plan tabs. Its left edge is a handle that resizes the pane.
///
/// The width follows the drag live and is stored, clamped to
/// [AppSettings.minRightPaneWidth]–[AppSettings.maxRightPaneWidth], when the drag ends.
/// {@endtemplate}
class WorkspaceRightPane extends StatefulWidget {
  /// {@macro workspace_right_pane}
  const WorkspaceRightPane({required this.maxWidth, super.key});

  /// The widest the pane may be right now: the chat keeps its minimum width. The stored width is
  /// not changed by this, it only limits what is shown and dragged.
  final double maxWidth;

  @override
  State<WorkspaceRightPane> createState() => _WorkspaceRightPaneState();
}

class _WorkspaceRightPaneState extends State<WorkspaceRightPane> {
  late final _scope = WorkspaceConfigInhWidget.of(context);

  /// Width of the last drag (unclamped), shown until the stored width catches up.
  double? _dragWidth;
  bool _dragging = false;

  /// The files the open chat changed: one result for the tab and its counter.
  late final ChangedFilesNotifier _changes = ChangedFilesNotifier(
    handle: _scope.dataController.chatHandle,
    projectRoot: () => _scope.selectedProject?.path ?? '',
    rootChanges: Listenable.merge(<Listenable>[_scope.projectsController, _scope.dataController]),
  );

  double get _storedWidth => _scope.settingsController.settings.rightPaneWidth;

  double _width() {
    final max = widget.maxWidth.clamp(AppSettings.minRightPaneWidth, AppSettings.maxRightPaneWidth);
    return (_dragWidth ?? _storedWidth).clamp(AppSettings.minRightPaneWidth, max);
  }

  @override
  void initState() {
    super.initState();
    _scope.settingsController.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _scope.settingsController.removeListener(_onSettingsChanged);
    _changes.dispose();
    super.dispose();
  }

  /// The settings were written (or the write failed): the stored width is the truth again.
  void _onSettingsChanged() {
    if (!_dragging && _dragWidth != null) setState(() => _dragWidth = null);
  }

  void _onDragUpdate(DragUpdateDetails details) => setState(() {
    _dragging = true;
    _dragWidth = (_dragWidth ?? _storedWidth) - details.delta.dx;
  });

  void _onDragEnd() {
    if (!_dragging) return;
    _dragging = false;
    _scope.setRightPaneWidth(_width());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    return ListenableBuilder(
      listenable: _scope.settingsController,
      builder: (context, child) => SizedBox(width: _width(), child: child),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                border: Border(left: BorderSide(color: colors.border)),
              ),
              child: ListenableBuilder(
                listenable: _scope.dataController,
                builder: (context, _) {
                  final tab = _scope.dataController.paneTab;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ListenableBuilder(
                        listenable: _scope.runController,
                        builder: (context, _) => ValueListenableBuilder<List<ChangedFile>>(
                          valueListenable: _changes,
                          builder: (context, files, _) => PaneTabs<RightPaneTab>(
                            tabs: <PaneTab<RightPaneTab>>[
                              PaneTab<RightPaneTab>(
                                id: RightPaneTab.changes,
                                label: localization.paneChanges,
                                count: files.isEmpty ? null : files.length,
                              ),
                              PaneTab<RightPaneTab>(
                                id: RightPaneTab.run,
                                label: localization.paneRun,
                                errors: _scope.runController.state.errorCount,
                              ),
                              PaneTab<RightPaneTab>(
                                id: RightPaneTab.plan,
                                label: localization.panePlan,
                              ),
                            ],
                            selected: tab,
                            onSelected: _scope.dataController.selectPaneTab,
                          ),
                        ),
                      ),
                      Expanded(
                        child: switch (tab) {
                          RightPaneTab.changes => ChangesTab(files: _changes),
                          RightPaneTab.plan => ValueListenableBuilder<ChatHandle?>(
                            valueListenable: _scope.dataController.chatHandle,
                            builder: (context, handle, _) =>
                                PlanTab(items: handle?.view.items ?? const <ChatItem>[]),
                          ),
                          RightPaneTab.run => RunTab(
                            projectId: _scope.dataController.projectId,
                            isPreview: _scope.runIsPreview,
                            devices: _scope.devicesController,
                            run: _scope.runController,
                            actions: _scope.runActionsController,
                            onSendError: _scope.sendRunErrorToAgent,
                            onAddWidget: _scope.addRunWidgetToMessage,
                            onOpenFile: (path, line) => _scope.openRunFile(path, line).ignore(),
                          ),
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                key: const ValueKey<String>('right-pane-resize-handle'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: (_) => _onDragEnd(),
                onHorizontalDragCancel: _onDragEnd,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
