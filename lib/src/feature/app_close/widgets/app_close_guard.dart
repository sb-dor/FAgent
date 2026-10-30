import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/app_close/controller/app_close_controller.dart';
import 'package:flutter_code_agent/src/feature/app_close/data/app_close_repository.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';

/// {@template app_close_guard}
/// Asks before quitting while agents work, and covers the app while they are
/// being stopped.
/// {@endtemplate}
class AppCloseGuard extends StatefulWidget {
  /// {@macro app_close_guard}
  const AppCloseGuard({required this.child, this.repository, super.key});

  /// The app.
  final Widget child;

  /// Overrides the window-backed repository (tests).
  final IAppCloseRepository? repository;

  @override
  State<AppCloseGuard> createState() => _AppCloseGuardState();
}

class _AppCloseGuardState extends State<AppCloseGuard> {
  late final AppCloseController _controller;

  @override
  void initState() {
    super.initState();
    final dependencies = Dependencies.of(context);
    _controller = AppCloseController(
      repository:
          widget.repository ??
          AppCloseRepositoryImpl(hub: dependencies.agentHub, database: dependencies.database),
    )..watch();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onState(AppCloseState previous, AppCloseState current) async {
    if (current case AppClose$ConfirmingState(:final busyChats)) {
      final localization = Localization.of(context);
      final quit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(localization.quitWhileBusyTitle),
          content: Text(localization.quitWhileBusyBody(busyChats)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(localization.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(localization.quit),
            ),
          ],
        ),
      );
      if (!mounted) return;
      (quit ?? false) ? _controller.confirm() : _controller.cancel();
    }
  }

  @override
  Widget build(BuildContext context) => StateConsumer<AppCloseController, AppCloseState>(
    controller: _controller,
    listener: (context, controller, previous, current) => _onState(previous, current),
    builder: (context, state, child) => Stack(
      children: <Widget>[
        child!,
        if (state is AppClose$InProgressState) ...<Widget>[
          const ModalBarrier(dismissible: false, color: Colors.black38),
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 16),
                    Text(Localization.of(context).stoppingAgents),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
    child: widget.child,
  );
}
