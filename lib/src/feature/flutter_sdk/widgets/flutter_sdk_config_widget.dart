import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/controller/flutter_sdk_controller.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/models/flutter_sdk.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// Gives the widgets of the Flutter section access to [FlutterSdkConfigWidgetState].
class FlutterSdkConfigInhWidget extends InheritedWidget {
  const FlutterSdkConfigInhWidget({super.key, required this.state, required super.child});

  final FlutterSdkConfigWidgetState state;

  static FlutterSdkConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<FlutterSdkConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'FlutterSdkConfigInhWidget was not found in element tree');
    return (widget! as FlutterSdkConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(FlutterSdkConfigInhWidget oldWidget) => false;
}

/// {@template flutter_sdk_config_widget}
/// Owns the controller of the Flutter section and keeps it on the selected project: the SDK is
/// read when the section opens and again whenever another project is selected.
///
/// It also owns what the buttons do beyond that: starting a chat that fixes a `flutter doctor`
/// finding, and telling the user that a preview option is not available yet.
/// {@endtemplate}
class FlutterSdkConfigWidget extends StatefulWidget {
  /// {@macro flutter_sdk_config_widget}
  const FlutterSdkConfigWidget({required this.child, super.key});

  /// The section.
  final Widget child;

  @override
  State<FlutterSdkConfigWidget> createState() => FlutterSdkConfigWidgetState();
}

class FlutterSdkConfigWidgetState extends State<FlutterSdkConfigWidget> {
  late final FlutterSdkController sdk;
  late final WorkspaceConfigWidgetState _workspace;
  bool _loaded = false;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _workspace = WorkspaceConfigInhWidget.of(context);
    sdk = FlutterSdkController(repository: Dependencies.of(context).flutterSdkRepository);
    _workspace.dataController.addListener(_onProject);
    _workspace.projectsController.addListener(_onProject);
    _onProject();
  }

  @override
  void dispose() {
    _workspace.dataController.removeListener(_onProject);
    _workspace.projectsController.removeListener(_onProject);
    sdk.dispose();
    super.dispose();
  }

  /// Notifies when the selected project may have changed.
  Listenable get projectListenable =>
      Listenable.merge(<Listenable>[_workspace.dataController, _workspace.projectsController]);

  /// The selected project; `null` when none is selected.
  Project? get project => _workspace.selectedProject;

  void _onProject() {
    // A selected project is unknown until the list of projects has arrived.
    final waiting =
        _workspace.dataController.projectId != null &&
        _workspace.projectsController.state is! Projects$CompletedState;
    if (waiting) return;
    final path = project?.path;
    if (_loaded && path == _loadedFor) return;
    _loaded = true;
    _loadedFor = path;
    sdk.load(path);
  }

  /// Reads the SDK of the selected project again.
  void retry() => sdk.load(_loadedFor);

  /// Runs `flutter doctor`.
  void runDoctor() => sdk.runDoctor();

  /// Starts a chat in the selected project that asks the agent to fix [check]. Does nothing
  /// without a project.
  void fixWithAgent(DoctorCheck check) {
    final project = this.project;
    if (project == null) return;
    final localization = Localization.of(context);
    final detail = check.detail;
    _workspace.createChat(
      projectId: project.id,
      draft: detail == null || detail.isEmpty
          ? localization.doctorFixDraftNoDetail(check.title)
          : localization.doctorFixDraft(check.title, detail),
    );
  }

  /// Says in a snack bar that an option arrives with [milestone].
  void showComingSoon(String milestone) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(Localization.of(context).comingInMilestone(milestone))));
  }

  @override
  Widget build(BuildContext context) => FlutterSdkConfigInhWidget(state: this, child: widget.child);
}
