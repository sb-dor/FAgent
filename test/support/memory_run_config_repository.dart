import 'dart:async';

import 'package:flutter_code_agent/app_run/data/launch_config_reader.dart';
import 'package:flutter_code_agent/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/app_run/models/run_arguments.dart';

/// In-memory run arguments (per project and app folder), selections, apps and `launch.json`
/// contents for tests. [saved] lists every [save] in order ([savedFor] with the app folder),
/// [savedSelections] every [saveSelected], [savedApps] every [saveSelectedApp].
class MemoryRunConfigRepository implements IRunConfigRepository {
  /// Creates the repository, optionally with [initial] arguments of the project roots, [selected]
  /// configurations, [selectedApps], runnable [apps] and [launch] contents per project. A project
  /// in [apps] is a monorepo, even with no apps.
  MemoryRunConfigRepository({
    Map<int, RunArguments> initial = const <int, RunArguments>{},
    Map<int, String> selected = const <int, String>{},
    Map<int, String> selectedApps = const <int, String>{},
    Map<int, List<String>> apps = const <int, List<String>>{},
    Map<int, LaunchConfigs> launch = const <int, LaunchConfigs>{},
  }) : _arguments = <(int, String), RunArguments>{
         for (final MapEntry(:key, :value) in initial.entries) (key, ''): value,
       },
       _selected = Map<int, String?>.of(selected),
       _selectedApps = Map<int, String?>.of(selectedApps),
       apps = Map<int, List<String>>.of(apps),
       launch = Map<int, LaunchConfigs>.of(launch);

  /// Every `(projectId, arguments)` passed to [save], in order.
  final List<(int, RunArguments)> saved = <(int, RunArguments)>[];

  /// Every `(projectId, appFolder, arguments)` passed to [save], in order.
  final List<(int, String, RunArguments)> savedFor = <(int, String, RunArguments)>[];

  /// Every `(projectId, name)` passed to [saveSelected], in order.
  final List<(int, String?)> savedSelections = <(int, String?)>[];

  /// Every `(projectId, appFolder)` passed to [saveSelectedApp], in order.
  final List<(int, String?)> savedApps = <(int, String?)>[];

  /// What [runnableApps] gives per project; none for a project not in it, which is not a monorepo
  /// ([isMonorepo]).
  final Map<int, List<String>> apps;

  /// What [launchConfigs] gives per project, read anew on every call; [LaunchConfigsMissing] for a
  /// project not in it. A test changes it to "edit" the file.
  final Map<int, LaunchConfigs> launch;

  /// The projects [launchConfigs] was called for, in order.
  final List<int> launchReads = <int>[];

  /// When set, [save] fails with it.
  Exception? saveError;

  final Map<(int, String), RunArguments> _arguments;
  final Map<int, String?> _selected;
  final Map<int, String?> _selectedApps;
  final List<((int, String), StreamController<RunArguments>)> _controllers =
      <((int, String), StreamController<RunArguments>)>[];
  final List<(int, StreamController<String?>)> _selectedControllers =
      <(int, StreamController<String?>)>[];
  final List<(int, StreamController<String?>)> _selectedAppControllers =
      <(int, StreamController<String?>)>[];

  @override
  Stream<RunArguments> watch(int projectId, {String appFolder = ''}) {
    final key = (projectId, appFolder);
    final controller = StreamController<RunArguments>();
    controller
      ..onListen = () {
        _controllers.add((key, controller));
        controller.add(_arguments[key] ?? const RunArguments());
      }
      ..onCancel = () {
        _controllers.removeWhere((entry) => entry.$2 == controller);
        return controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> save(int projectId, RunArguments arguments, {String appFolder = ''}) async {
    saved.add((projectId, arguments));
    savedFor.add((projectId, appFolder, arguments));
    final error = saveError;
    if (error != null) throw error;
    final key = (projectId, appFolder);
    _arguments[key] = arguments;
    for (final (id, controller) in List.of(_controllers)) {
      if (id == key && !controller.isClosed) controller.add(arguments);
    }
  }

  @override
  Stream<String?> watchSelected(int projectId) {
    final controller = StreamController<String?>();
    controller
      ..onListen = () {
        _selectedControllers.add((projectId, controller));
        controller.add(_selected[projectId]);
      }
      ..onCancel = () {
        _selectedControllers.removeWhere((entry) => entry.$2 == controller);
        return controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> saveSelected(int projectId, String? name) async {
    savedSelections.add((projectId, name));
    _selected[projectId] = name;
    for (final (id, controller) in List.of(_selectedControllers)) {
      if (id == projectId && !controller.isClosed) controller.add(name);
    }
  }

  @override
  Stream<String?> watchSelectedApp(int projectId) {
    final controller = StreamController<String?>();
    controller
      ..onListen = () {
        _selectedAppControllers.add((projectId, controller));
        controller.add(_selectedApps[projectId]);
      }
      ..onCancel = () {
        _selectedAppControllers.removeWhere((entry) => entry.$2 == controller);
        return controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> saveSelectedApp(int projectId, String? appFolder) async {
    savedApps.add((projectId, appFolder));
    _selectedApps[projectId] = appFolder;
    for (final (id, controller) in List.of(_selectedAppControllers)) {
      if (id == projectId && !controller.isClosed) controller.add(appFolder);
    }
  }

  @override
  Future<bool> isMonorepo(int projectId) async => apps.containsKey(projectId);

  @override
  Future<List<String>> runnableApps(int projectId) async => apps[projectId] ?? const <String>[];

  @override
  Future<LaunchConfigs> launchConfigs(int projectId) async {
    launchReads.add(projectId);
    return launch[projectId] ?? const LaunchConfigsMissing();
  }
}
