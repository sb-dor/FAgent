import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';

/// {@template creation_chip}
/// The sidebar chip of the creation that is running or waits to be acknowledged: "Creating `name` ·
/// N/M", "`name`: done" or "`name`: error". Tapping it calls [onOpen] (the dialog opens on the
/// progress); a finished creation also has a ✕ that calls [onHide].
///
/// It takes no space while the [controller] is idle.
/// {@endtemplate}
class CreationChip extends StatelessWidget {
  /// {@macro creation_chip}
  const CreationChip({
    required this.controller,
    required this.onOpen,
    required this.onHide,
    super.key,
  });

  /// The window's creation.
  final ProjectCreationController controller;

  /// Opens the progress dialog.
  final VoidCallback onOpen;

  /// Hides the chip of a finished creation.
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final localization = Localization.of(context);
      final colors = context.colors;
      final (label, background, icon, finished) = switch (controller.state) {
        ProjectCreation$IdleState() => (null, colors.surface, const SizedBox.shrink(), false),
        ProjectCreation$RunningState(:final request, :final steps) => (
          localization.newProjectChipRunning(
            request.name,
            steps.where((step) => step.status == CreationStepStatus.done).length,
            steps.length,
          ),
          colors.accentSoft,
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
          ),
          false,
        ),
        ProjectCreation$CompletedState(:final request) => (
          localization.newProjectChipDone(request.name),
          colors.okSoft,
          Icon(Icons.check, size: 14, color: colors.ok),
          true,
        ),
        ProjectCreation$FailedState(:final request) => (
          localization.newProjectChipFailed(request.name),
          colors.dangerSoft,
          Icon(Icons.close, size: 14, color: colors.danger),
          true,
        ),
      };
      if (label == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Material(
          key: const ValueKey<String>('creation-chip'),
          color: background,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
          child: Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: onOpen,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(8, 6, finished ? 0 : 8, 6),
                    child: Row(
                      children: <Widget>[
                        SizedBox(width: 14, height: 14, child: Center(child: icon)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall!
                                .copyWith(color: colors.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (finished)
                IconButton(
                  key: const ValueKey<String>('creation-chip-hide'),
                  tooltip: localization.newProjectChipHide,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.close, size: 14, color: colors.muted),
                  onPressed: onHide,
                ),
            ],
          ),
        ),
      );
    },
  );
}
