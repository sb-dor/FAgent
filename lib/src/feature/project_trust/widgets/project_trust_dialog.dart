import 'package:control/control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/initialization/models/dependencies.dart';
import 'package:flutter_code_agent/src/feature/project_trust/controller/project_trust_controller.dart';
import 'package:flutter_code_agent/src/feature/project_trust/data/project_trust_repository.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';

/// {@template project_trust_dialog}
/// Asks whether agents may run the folder's own settings and hooks, listing
/// the ones it found. No agent session starts in an untrusted folder.
/// {@endtemplate}
class ProjectTrustDialog extends StatefulWidget {
  /// {@macro project_trust_dialog}
  const ProjectTrustDialog({required this.project, super.key});

  /// Shows the dialog; `true` when the user trusted the folder.
  static Future<bool> show(BuildContext context, Project project) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => ProjectTrustDialog(project: project),
      ) ??
      false;

  /// Folder to trust.
  final Project project;

  @override
  State<ProjectTrustDialog> createState() => _ProjectTrustDialogState();
}

class _ProjectTrustDialogState extends State<ProjectTrustDialog> {
  late final ProjectTrustController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ProjectTrustController(
      repository: ProjectTrustRepositoryImpl(database: Dependencies.of(context).database),
    )..inspect(widget.project.path);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final theme = Theme.of(context);
    return StateConsumer<ProjectTrustController, ProjectTrustState>(
      controller: _controller,
      listener: (context, controller, previous, current) {
        if (current is ProjectTrust$CompletedState) Navigator.pop(context, true);
      },
      builder: (context, state, _) => PopScope(
        canPop: state is! ProjectTrust$InProgressState,
        child: AlertDialog(
          title: Text(localization.trustTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(localization.trustBody(widget.project.path)),
                const SizedBox(height: 12),
                switch (state) {
                  ProjectTrust$LoadedState(:final settingsFiles) when settingsFiles.isNotEmpty =>
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(localization.trustFiles, style: theme.textTheme.labelLarge),
                        for (final file in settingsFiles)
                          Text(
                            '• $file',
                            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo'),
                          ),
                      ],
                    ),
                  ProjectTrust$LoadedState() => Text(
                    localization.trustNoFiles,
                    style: theme.textTheme.bodySmall,
                  ),
                  ProjectTrust$ErrorState(:final error) => Text(
                    '$error',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  _ => const LinearProgressIndicator(),
                },
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(localization.cancel),
            ),
            FilledButton(
              onPressed: state is ProjectTrust$InProgressState
                  ? null
                  : () => _controller.trust(widget.project.id),
              child: Text(localization.trustAllow),
            ),
          ],
        ),
      ),
    );
  }
}
