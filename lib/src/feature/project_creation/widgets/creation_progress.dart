import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/project_creation/controller/project_creation_controller.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/creation_step.dart';
import 'package:flutter_code_agent/src/feature/project_creation/widgets/new_project_header.dart';

/// How many of the last output lines of a step are shown.
const int kCreationOutputLines = 6;

/// {@template creation_progress}
/// The New project dialog once the creation has started: the title, every step with its status,
/// duration and last output lines, a note, and the buttons.
///
/// While the creation runs it offers "Minimize" (closes the dialog, the creation goes on) and the
/// agent chat; when it has finished (completed or failed) it offers "Done", which calls [onDone].
/// It shows nothing for an idle [controller]: the dialog shows the form then.
/// {@endtemplate}
class CreationProgress extends StatelessWidget {
  /// {@macro creation_progress}
  const CreationProgress({required this.controller, required this.onDone, super.key});

  /// The window's creation.
  final ProjectCreationController controller;

  /// Called by "Done": closes the dialog and resets the [controller].
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final localization = Localization.of(context);
      final state = controller.state;
      final (request, steps, error) = switch (state) {
        ProjectCreation$IdleState() => (null, const <CreationStep>[], null),
        ProjectCreation$RunningState(:final request, :final steps) => (request, steps, null),
        ProjectCreation$CompletedState(:final request, :final steps) => (request, steps, null),
        ProjectCreation$FailedState(:final request, :final steps, :final error) => (
          request,
          steps,
          error,
        ),
      };
      if (request == null) return const SizedBox.shrink();
      final title = switch (state) {
        ProjectCreation$CompletedState() =>
          controller.isPreview
              ? localization.newProjectCreatedPreview(request.name)
              : localization.newProjectCreated(request.name),
        ProjectCreation$FailedState() => localization.newProjectFailed(request.name),
        _ => localization.newProjectCreating(request.name),
      };
      final running = state is ProjectCreation$RunningState;
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
                  const SizedBox(height: 12),
                  _Note(preview: controller.isPreview),
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
              child: running ? _runningButtons(context) : _doneButton(context),
            ),
          ),
        ],
      );
    },
  );

  Widget _runningButtons(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    return Row(
      children: <Widget>[
        Flexible(
          child: TextButton(
            key: const ValueKey<String>('creation-open-chat'),
            style: TextButton.styleFrom(
              foregroundColor: colors.muted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium - 2),
              ),
            ),
            // The agent's chat exists only with the real creation (milestone M4).
            onPressed: () =>
                ScaffoldMessenger.maybeOf(context)
                    ?.showSnackBar(SnackBar(content: Text(localization.comingInMilestone('M4')))),
            child: Text(
              localization.newProjectOpenAgentChat,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const Spacer(),
        const SizedBox(width: 8),
        OutlinedButton(
          key: const ValueKey<String>('creation-minimize'),
          // Takes the focus, so that Esc reaches the dialog.
          autofocus: true,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.text,
            side: BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.medium - 2),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localization.newProjectMinimize),
        ),
      ],
    );
  }

  Widget _doneButton(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: FilledButton(
      key: const ValueKey<String>('creation-done'),
      autofocus: true,
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium - 2)),
      ),
      onPressed: onDone,
      child: Text(Localization.of(context).newProjectDone),
    ),
  );
}

/// The explanation under the steps; in a preview it says that nothing is created.
class _Note extends StatelessWidget {
  const _Note({required this.preview});

  final bool preview;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(color: context.colors.muted);
    if (!preview) return Text(localization.newProjectProgressNote, style: style);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        const PreviewBadge(),
        Text(localization.newProjectPreviewNote, style: style),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final CreationStep step;

  static String _label(BuildContext context, CreationStepKind kind) => switch (kind) {
    CreationStepKind.flutterCreate => Localization.of(context).newProjectStepFlutterCreate,
    CreationStepKind.gitInit => Localization.of(context).newProjectStepGitInit,
    CreationStepKind.agentSetup => Localization.of(context).newProjectStepAgentSetup,
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
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: _label(context, step.kind),
                        style: active ? const TextStyle(fontWeight: FontWeight.w600) : null,
                      ),
                      if (step.kind == CreationStepKind.agentSetup)
                        TextSpan(
                          text: ' · ${localization.newProjectAgentName}',
                          style: TextStyle(color: colors.muted),
                        ),
                    ],
                  ),
                  style: textTheme.bodyMedium!.copyWith(
                    color: step.status == CreationStepStatus.pending ? colors.muted : colors.text,
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
