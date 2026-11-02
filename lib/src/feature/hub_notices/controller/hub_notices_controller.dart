import 'dart:async';

import 'package:control/control.dart';
import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';
import 'package:flutter_code_agent/src/feature/hub_notices/data/hub_notices_repository.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'hub_notices_controller.freezed.dart';

@freezed
sealed class HubNoticesState with _$HubNoticesState {
  const factory HubNoticesState.initial() = HubNotices$InitialState;

  /// [notice] just happened; [count] tells repeated equal notices apart.
  const factory HubNoticesState.completed({required HubNotice notice, required int count}) =
      HubNotices$CompletedState;

  /// The app's MCP server did not start: the agents work without the Flutter tools.
  const factory HubNoticesState.flutterToolsUnavailable() = HubNotices$FlutterToolsUnavailableState;
}

/// The latest hub notice, for a snackbar.
final class HubNoticesController extends StateController<HubNoticesState>
    with SequentialControllerHandler {
  HubNoticesController({
    required this._repository,
    super.initialState = const HubNoticesState.initial(),
  });

  final IHubNoticesRepository _repository;
  StreamSubscription<HubNotice>? _subscription;
  var _count = 0;

  /// Starts listening; first tells whether the Flutter tools are unavailable.
  void watch() => handle(() async {
    await _subscription?.cancel();
    if (_repository.flutterToolsUnavailable()) {
      setState(const HubNoticesState.flutterToolsUnavailable());
    }
    _subscription = _repository.notices().listen(
      (notice) => setState(HubNoticesState.completed(notice: notice, count: ++_count)),
    );
  });

  @override
  void dispose() {
    _subscription?.cancel().ignore();
    super.dispose();
  }
}
