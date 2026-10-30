import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/common/database/database.dart';
import 'package:flutter_code_agent/src/common/shell_env/shell_environment.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/app_run_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/devices_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/widget_picker_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/widget/dependencies_scope.dart';
import 'package:flutter_code_agent/src/feature/skills/data/skills_repository.dart';

/// {@template dependencies}
/// Application dependencies.
/// {@endtemplate}
class Dependencies {
  /// {@macro dependencies}
  Dependencies();

  /// The state from the closest instance of this class.
  ///
  /// {@macro dependencies}
  factory Dependencies.of(BuildContext context) => DependenciesScope.of(context);

  /// Injest dependencies to the widgets tree.
  Widget inject({required Widget child, Key? key}) =>
      DependenciesScope(dependencies: this, key: key, child: child);

  /// Database
  late final AppDatabase database;

  /// Login-shell environment for every child process (agents, `flutter`, `git`).
  late final ShellEnvironment shellEnvironment;

  /// Agent processes and the runtime state of every chat.
  late final AgentHub agentHub;

  /// The devices the app can run on.
  late final IDevicesRepository devicesRepository;

  /// Runs of the projects' apps (`flutter run`).
  late final IAppRunRepository appRunRepository;

  /// Picks a widget in a running app.
  late final IWidgetPickerRepository widgetPickerRepository;

  /// Skills and rules: the built-in ones, the user's and the projects', and where they are on.
  late final ISkillsRepository skillsRepository;

  @override
  String toString() => 'Dependencies{}';
}
