import 'package:control/control.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/data/mcp_servers_repository.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'mcp_server_actions_controller.freezed.dart';

/// What an import of a `.mcp.json` did: the names that were added and the ones left out with the
/// reason.
typedef McpImportSummary = ({List<String> added, List<(String name, String reason)> skipped});

@freezed
sealed class McpServerActionsState with _$McpServerActionsState {
  /// No action has been taken.
  const factory McpServerActionsState.idle() = McpServerActions$IdleState;

  /// An action is running.
  const factory McpServerActionsState.processing() = McpServerActions$ProcessingState;

  /// The last action finished; [imported] is the outcome of an import and `null` for the others.
  const factory McpServerActionsState.completed({McpImportSummary? imported}) =
      McpServerActions$CompletedState;

  /// The last action failed with [error], for example an `InvalidMcpServerException`.
  const factory McpServerActionsState.failed({required Object error}) =
      McpServerActions$FailedState;
}

/// The buttons of the MCP servers section: add, remove, switch on or off and import.
///
/// One action at a time: a tap during another one is dropped. The result shows up in the list
/// observed through `McpServersController`.
final class McpServerActionsController extends StateController<McpServerActionsState>
    with DroppableControllerHandler {
  McpServerActionsController({
    required this._repository,
    super.initialState = const McpServerActionsState.idle(),
  });

  final IMcpServersRepository _repository;

  /// Adds the server of [draft]; fails with an `InvalidMcpServerException` when it is not valid.
  void add(McpServerDraft draft) => _run(() async {
    await _repository.add(draft);
    return null;
  });

  /// Removes the server [id] the user added.
  void remove(String id) => _run(() async {
    await _repository.remove(id);
    return null;
  });

  /// Turns [id] on or off for everything ([projectId] is `null`; the user's servers only) or for
  /// one project.
  void setEnabled(String id, {required bool enabled, int? projectId}) => _run(() async {
    await _repository.setEnabled(id, enabled: enabled, projectId: projectId);
    return null;
  });

  /// Adds the servers of the `.mcp.json` at [path].
  void importMcpJson(String path) => _run(() => _repository.importMcpJson(path));

  void _run(Future<McpImportSummary?> Function() action) => handle(() async {
    setState(const McpServerActionsState.processing());
    final imported = await action();
    setState(McpServerActionsState.completed(imported: imported));
  }, error: (error, stackTrace) async => setState(McpServerActionsState.failed(error: error)));
}
