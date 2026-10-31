import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/prompt_sending/models/slash_command.dart';

/// The list of commands under a typed `/`, in sections (skills, app, then agent) in the order of
/// [commands]. [highlighted] is the row Enter would insert; commands that are not enabled are
/// dimmed with their hint and cannot be chosen.
class CommandSuggestions extends StatelessWidget {
  /// Creates the list.
  const CommandSuggestions({
    super.key,
    required this.commands,
    required this.highlighted,
    required this.onSelected,
  });

  /// Rows to show.
  final List<SlashCommand> commands;

  /// Index of the row Enter would insert; `-1` for none.
  final int highlighted;

  /// An enabled command was clicked.
  final ValueChanged<SlashCommand> onSelected;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final (index, command) in commands.indexed) ...<Widget>[
              if (index == 0 || commands[index - 1].source != command.source)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: Text(
                    switch (command.source) {
                      SlashSource.skill => localization.slashSectionSkills,
                      SlashSource.app => localization.slashSectionApp,
                      SlashSource.agent => localization.slashSectionAgent,
                    },
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: context.colors.muted, fontWeight: FontWeight.w600),
                  ),
                ),
              _CommandRow(
                command: command,
                selected: index == highlighted,
                onTap: command.enabled ? () => onSelected(command) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommandRow extends StatefulWidget {
  const _CommandRow({required this.command, required this.selected, required this.onTap});

  final SlashCommand command;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_CommandRow> createState() => _CommandRowState();
}

class _CommandRowState extends State<_CommandRow> {
  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_CommandRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.selected) _reveal();
  }

  /// Scrolls the highlighted row into view.
  void _reveal() {
    if (!widget.selected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Scrollable.ensureVisible(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final command = widget.command;
    final localization = Localization.of(context);
    final description = switch (command.name) {
      'run' when command.source == SlashSource.app => localization.commandRun,
      'reload' when command.source == SlashSource.app => localization.commandReload,
      'restart' when command.source == SlashSource.app => localization.commandRestart,
      'screenshot' when command.source == SlashSource.app => localization.commandScreenshot,
      _ => command.description,
    };
    final hint = command.hint;
    return Opacity(
      opacity: command.enabled ? 1 : 0.5,
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          selected: widget.selected,
          selectedTileColor: context.colors.accentSoft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
          title: Text('/${command.name}', style: AppText.mono(context, size: 13)),
          subtitle: description == null
              ? null
              : Text(description, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: !command.enabled && hint != null
              ? Text(
                  localization.comingInMilestone(hint),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: context.colors.muted),
                )
              : null,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}
