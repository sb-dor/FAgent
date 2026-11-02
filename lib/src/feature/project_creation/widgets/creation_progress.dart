import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/new_project_header.dart';

/// How many of the last output lines of a step are shown.
const int kCreationOutputLines = 6;

/// {@template creation_progress}
/// The New project dialog once the creation has started: the title, every step with its status,
/// duration and last output lines, and the buttons.
///
/// While the creation runs it offers "Stop" (kills the running command, the creation then ends as
/// failed) and "Minimize" (closes the dialog, the creation goes on). When it has finished
/// (completed or failed) it offers "Close", which calls [onClose], and, if the project was added
/// to the app, "Open project", which calls [onOpenProject] with its id. It shows nothing for an
/// idle [controller]: the dialog shows the form then.
/// {@endtemplate}
class CreationProgress extends StatelessWidget {
  /// {@macro creation_progress}
  const CreationProgress({
    required this.controller,
    required this.onClose,
    required this.onOpenProject,
    super.key,
  });

  /// The window's creation.
  final ProjectCreationController controller;

  /// Called by "Close": closes the dialog and resets the [controller].
  final VoidCallback onClose;

  /// Called by "Open project" with the id of the created project: closes the dialog, resets the
  /// [controller] and opens the project.
  final void Function(int projectId) onOpenProject;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final localization = Localization.of(context);
      final state = controller.state;
      final (request, steps, error, projectId) = switch (state) {
        ProjectCreation$IdleState() => (null, const <CreationStep>[], null, null),
        ProjectCreation$RunningState(:final request, :final steps) => (request, steps, null, null),
        ProjectCreation$CompletedState(:final request, :final steps, :final projectId) => (
          request,
          steps,
          null,
          projectId,
        ),
        ProjectCreation$FailedState(:final request, :final steps, :final error, :final projectId) =>
          (request, steps, error, projectId),
      };
      if (request == null) return const SizedBox.shrink();
      final title = switch (state) {
        ProjectCreation$CompletedState() => localization.newProjectCreated(request.name),
        ProjectCreation$FailedState() => localization.newProjectFailed(request.name),
        _ => localization.newProjectCreating(request.name),
      };
      final running = state is ProjectCreation$RunningState;
      final stopping = state is ProjectCreation$RunningState && state.stopping;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NewProjectHeader(title: title),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final step in steps) _StepRow(step: step),
                  if (error != null && error is! CreationStepFailed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '$error',
                        style: AppText.mono(context).copyWith(color: context.colors.danger),
                      ),
                    ),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.surfaceAlt,
              border: Border(top: BorderSide(color: context.colors.border)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: running
                  ? _runningButtons(context, stopping: stopping)
                  : _finishedButtons(context, projectId),
            ),
          ),
        ],
      );
    },
  );

  Widget _runningButtons(BuildContext context, {required bool stopping}) {
    final localization = Localization.of(context);
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        TextButton(
          key: const ValueKey<String>('creation-stop'),
          style: TextButton.styleFrom(
            foregroundColor: colors.danger,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium - 2),
            ),
          ),
          onPressed: stopping ? null : controller.stop,
          child: Text(stopping ? localization.newProjectStopping : localization.newProjectStop),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: const ValueKey<String>('creation-minimize'),
          // Takes the focus, so that Esc reaches the dialog.
          autofocus: true,
          style: _outlined(colors),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localization.newProjectMinimize),
        ),
      ],
    );
  }

  Widget _finishedButtons(BuildContext context, int? projectId) {
    final localization = Localization.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        OutlinedButton(
          key: const ValueKey<String>('creation-close'),
          autofocus: projectId == null,
          style: _outlined(context.colors),
          onPressed: onClose,
          child: Text(localization.newProjectClose),
        ),
        if (projectId != null) ...<Widget>[
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey<String>('creation-open-project'),
            autofocus: true,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium - 2),
              ),
            ),
            onPressed: () => onOpenProject(projectId),
            child: Text(localization.newProjectOpenProject),
          ),
        ],
      ],
    );
  }

  static ButtonStyle _outlined(AppColors colors) => OutlinedButton.styleFrom(
    foregroundColor: colors.text,
    side: BorderSide(color: colors.border),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium - 2)),
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final CreationStep step;

  static String _label(BuildContext context, CreationStepKind kind) => switch (kind) {
    CreationStepKind.flutterCreate => Localization.of(context).newProjectStepFlutterCreate,
    CreationStepKind.gitInit => Localization.of(context).newProjectStepGitInit,
    CreationStepKind.skeleton => Localization.of(context).newProjectStepSkeleton,
    CreationStepKind.analyze => Localization.of(context).newProjectStepAnalyze,
    CreationStepKind.firstCommit => Localization.of(context).newProjectStepFirstCommit,
  };

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final took = step.took;
    final output = step.output.length > kCreationOutputLines
        ? step.output.sublist(step.output.length - kCreationOutputLines)
        : step.output;
    final active = step.status == CreationStepStatus.running;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(width: 18, height: 20, child: Center(child: _StatusIcon(step.status))),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _label(context, step.kind),
                  style: textTheme.bodyMedium!.copyWith(
                    color: step.status == CreationStepStatus.pending ? colors.muted : colors.text,
                    fontWeight: active ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (took != null) ...<Widget>[
                const SizedBox(width: 8),
                Text(
                  localization.newProjectStepTook(
                    math.max(1, (took.inMilliseconds / 1000).round()),
                  ),
                  style: textTheme.bodySmall!.copyWith(color: colors.muted),
                ),
              ],
            ],
          ),
          if (output.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final line in output)
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono(context, size: 11).copyWith(color: colors.muted),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon(this.status);

  final CreationStepStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return switch (status) {
      CreationStepStatus.pending => Text(
        '○',
        style: TextStyle(color: colors.muted, fontSize: 13, height: 1),
      ),
      CreationStepStatus.running => SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.accent),
      ),
      CreationStepStatus.done => Text(
        '✓',
        style: TextStyle(color: colors.ok, fontSize: 14, fontWeight: FontWeight.w700, height: 1),
      ),
      CreationStepStatus.failed => Text(
        '✕',
        style: TextStyle(
          color: colors.danger,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    };
  }
}
