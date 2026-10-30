import 'dart:async';

import 'package:flutter_code_agent/src/common/acp/agent_hub.dart';

/// Problems the agent hub could not record in a chat's journal (the
/// database failed), shown to the user right away.
abstract interface class IHubNoticesRepository {
  /// Notices as they happen. Ends when the hub is disposed or the
  /// subscription is cancelled.
  Stream<HubNotice> notices();
}

/// AgentHub-backed [IHubNoticesRepository].
final class HubNoticesRepositoryImpl implements IHubNoticesRepository {
  /// Creates the repository.
  HubNoticesRepositoryImpl({required this._hub});

  final AgentHub _hub;

  @override
  Stream<HubNotice> notices() {
    final controller = StreamController<HubNotice>();
    StreamSubscription<HubNotice>? subscription;
    controller
      ..onListen = () {
        subscription = _hub.notices.listen(
          controller.add,
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
        );
      }
      ..onCancel = () async {
        await subscription?.cancel();
        if (!controller.isClosed) await controller.close();
      };
    return controller.stream;
  }
}
