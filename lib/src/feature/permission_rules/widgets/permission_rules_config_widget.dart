import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/controller/permission_rules_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/controller/projects_controller.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';

/// Gives the widgets of the Permissions section access to [PermissionRulesConfigWidgetState].
class PermissionRulesConfigInhWidget extends InheritedWidget {
  const PermissionRulesConfigInhWidget({super.key, required this.state, required super.child});

  final PermissionRulesConfigWidgetState state;

  static PermissionRulesConfigWidgetState of(BuildContext context) {
    final widget = context
        .getElementForInheritedWidgetOfExactType<PermissionRulesConfigInhWidget>()
        ?.widget;
    assert(widget != null, 'PermissionRulesConfigInhWidget was not found in element tree');
    return (widget! as PermissionRulesConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(PermissionRulesConfigInhWidget oldWidget) => false;
}

/// {@template permission_rules_config_widget}
/// Owns the controller of the Permissions section and keeps it up to date: the rules are read when
/// the section opens, again whenever the list of projects changes and on [refresh].
///
/// A rule that could not be removed is reported in a snack bar.
/// {@endtemplate}
class PermissionRulesConfigWidget extends StatefulWidget {
  /// {@macro permission_rules_config_widget}
  const PermissionRulesConfigWidget({required this.child, super.key});

  /// The section.
  final Widget child;

  @override
  State<PermissionRulesConfigWidget> createState() => PermissionRulesConfigWidgetState();
}

class PermissionRulesConfigWidgetState extends State<PermissionRulesConfigWidget> {
  late final PermissionRulesController rules;
  late final ProjectsController _projects;
  List<Project>? _loadedFor;

  @override
  void initState() {
    super.initState();
    rules = PermissionRulesController(
      repository: Dependencies.of(context).permissionRulesRepository,
      onRemoveFailed: _onRemoveFailed,
    );
    _projects = WorkspaceConfigInhWidget.of(context).projectsController..addListener(_onProjects);
    _onProjects();
  }

  @override
  void dispose() {
    _projects.removeListener(_onProjects);
    rules.dispose();
    super.dispose();
  }

  /// Notifies when the projects change.
  Listenable get projectsListenable => _projects;

  /// The projects whose rules are shown; `null` until the list of projects has arrived.
  List<Project>? get projects => switch (_projects.state) {
    Projects$CompletedState(:final projects) => projects,
    _ => null,
  };

  void _onProjects() {
    final current = projects;
    if (current == null || listEquals(current, _loadedFor)) return;
    _loadedFor = current;
    rules.load(current);
  }

  /// Reads the rules of all projects again.
  void refresh() {
    final current = projects;
    if (current == null) return;
    _loadedFor = current;
    rules.load(current);
  }

  void _onRemoveFailed(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(Localization.of(context).permissionsRemoveFailed('$error'))),
    );
  }

  @override
  Widget build(BuildContext context) =>
      PermissionRulesConfigInhWidget(state: this, child: widget.child);
}
