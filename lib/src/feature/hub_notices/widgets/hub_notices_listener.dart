import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/hub_notices/controller/hub_notices_controller.dart';
import 'package:flutter_code_agent/src/feature/hub_notices/data/hub_notices_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';

/// {@template hub_notices_listener}
/// Shows problems the app could not record in a chat (e.g. a failed database
/// write), and a failed start of the app's MCP server, as snackbars.
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
    final dependencies = Dependencies.of(context);
    _controller = HubNoticesController(
      repository: HubNoticesRepositoryImpl(
        hub: dependencies.agentHub,
        appMcpServer: dependencies.appMcpServer,
      ),
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
      final message = switch (current) {
        HubNotices$InitialState() => null,
        HubNotices$CompletedState(:final notice) => notice.message,
        HubNotices$FlutterToolsUnavailableState() => Localization.of(
          context,
        ).flutterToolsUnavailable,
      };
      if (message == null) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          duration: const Duration(seconds: 8),
        ),
      );
    },
    child: widget.child,
  );
}
