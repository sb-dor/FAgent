import 'dart:async';

import 'package:flutter_code_agent/src/feature/app_run/data/run_config_repository.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/run_arguments.dart';

/// In-memory run arguments for tests. [saved] lists every [save] in order.
class MemoryRunConfigRepository implements IRunConfigRepository {
  /// Creates the repository, optionally with [initial] arguments per project.
  MemoryRunConfigRepository({Map<int, RunArguments> initial = const <int, RunArguments>{}})
    : _arguments = Map<int, RunArguments>.of(initial);

  /// Every `(projectId, arguments)` passed to [save], in order.
  final List<(int, RunArguments)> saved = <(int, RunArguments)>[];

  /// When set, [save] fails with it.
  Exception? saveError;

  final Map<int, RunArguments> _arguments;
  final List<(int, StreamController<RunArguments>)> _controllers =
      <(int, StreamController<RunArguments>)>[];

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
}
