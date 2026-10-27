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

  /// Starts listening.
  void watch() => handle(() async {
    await _subscription?.cancel();
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
