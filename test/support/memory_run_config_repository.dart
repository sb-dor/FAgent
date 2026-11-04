import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/data/launch_config_reader.dart';
import 'package:flutter_code_agent/src/feature/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';

/// In-memory run arguments, selections and `launch.json` contents for tests. [saved] lists every
/// [save] in order, [savedSelections] every [saveSelected].
class MemoryRunConfigRepository implements IRunConfigRepository {
  /// Creates the repository, optionally with [initial] arguments, [selected] configurations and
  /// [launch] contents per project.
  MemoryRunConfigRepository({
    Map<int, RunArguments> initial = const <int, RunArguments>{},
    Map<int, String> selected = const <int, String>{},
    Map<int, LaunchConfigs> launch = const <int, LaunchConfigs>{},
  }) : _arguments = Map<int, RunArguments>.of(initial),
       _selected = Map<int, String?>.of(selected),
       launch = Map<int, LaunchConfigs>.of(launch);

  /// Every `(projectId, arguments)` passed to [save], in order.
  final List<(int, RunArguments)> saved = <(int, RunArguments)>[];

  /// Every `(projectId, name)` passed to [saveSelected], in order.
  final List<(int, String?)> savedSelections = <(int, String?)>[];

  /// What [launchConfigs] gives per project, read anew on every call; [LaunchConfigsMissing] for a
  /// project not in it. A test changes it to "edit" the file.
  final Map<int, LaunchConfigs> launch;

  /// The projects [launchConfigs] was called for, in order.
  final List<int> launchReads = <int>[];

  /// When set, [save] fails with it.
  Exception? saveError;

  final Map<int, RunArguments> _arguments;
  final Map<int, String?> _selected;
  final List<(int, StreamController<RunArguments>)> _controllers =
      <(int, StreamController<RunArguments>)>[];
  final List<(int, StreamController<String?>)> _selectedControllers =
      <(int, StreamController<String?>)>[];

  @override
  Stream<RunArguments> watch(int projectId) {
    final controller = StreamController<RunArguments>();
    controller
      ..onListen = () {
        _controllers.add((projectId, controller));
        controller.add(_arguments[projectId] ?? const RunArguments());
      }
      ..onCancel = () {
        _controllers.removeWhere((entry) => entry.$2 == controller);
        return controller.close();
      };
    return controller.stream;
  }

  @override
  Future<void> save(int projectId, RunArguments arguments) async {
    saved.add((projectId, arguments));
    final error = saveError;
    if (error != null) throw error;
    _arguments[projectId] = arguments;
    for (final (id, controller) in List.of(_controllers)) {
      if (id == projectId && !controller.isClosed) controller.add(arguments);
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
  Future<LaunchConfigs> launchConfigs(int projectId) async {
    launchReads.add(projectId);
    return launch[projectId] ?? const LaunchConfigsMissing();
  }
}
