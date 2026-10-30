import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/feature/hub_notices/controller/hub_notices_controller.dart';
import 'package:flutter_code_agent/src/feature/hub_notices/data/hub_notices_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';

/// {@template hub_notices_listener}
/// Shows problems the app could not record in a chat (e.g. a failed database
/// write) as snackbars.
/// {@endtemplate}
class HubNoticesListener extends StatefulWidget {
  /// {@macro hub_notices_listener}
  const HubNoticesListener({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  State<HubNoticesListener> createState() => _HubNoticesListenerState();
}

class _HubNoticesListenerState extends State<HubNoticesListener> {
  late final HubNoticesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HubNoticesController(
      repository: HubNoticesRepositoryImpl(hub: Dependencies.of(context).agentHub),
    )..watch();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StateConsumer<HubNoticesController, HubNoticesState>(
    controller: _controller,
    buildWhen: (previous, current) => false,
    listener: (context, controller, previous, current) {
      if (current case HubNotices$CompletedState(:final notice)) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(notice.message),
            behavior: SnackBarBehavior.floating,
            showCloseIcon: true,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    },
    child: widget.child,
  );
}
