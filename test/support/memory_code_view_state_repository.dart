import 'package:flutter_code_agent/src/feature/code_view/data/code_view_state_repository.dart';
import 'package:flutter_code_agent/src/feature/code_view/models/code_view_state.dart';

/// [ICodeViewStateRepository] in memory, with every save recorded.
final class MemoryCodeViewStateRepository implements ICodeViewStateRepository {
  /// Creates the repository with [states] already saved.
  MemoryCodeViewStateRepository([Map<int, CodeViewState>? states])
    : states = <int, CodeViewState>{...?states};

  /// The saved state of each project.
  final Map<int, CodeViewState> states;

  /// Every save in order.
  final List<(int, CodeViewState)> saves = <(int, CodeViewState)>[];

  @override
  Future<CodeViewState> load(int projectId) async => states[projectId] ?? const CodeViewState();

  @override
  Future<void> save(int projectId, CodeViewState state) async {
    states[projectId] = state;
    saves.add((projectId, state));
  }
}
