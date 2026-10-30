import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/projects/models/project.dart';

/// {@template workspace_project_header}
/// The title of a project group: a ▸/▾ chevron and the project name, which collapse the group,
/// a button for a new chat that shows while the pointer is over the row, and the ⋯ menu button.
/// {@endtemplate}
class WorkspaceProjectHeader extends StatefulWidget {
  /// {@macro workspace_project_header}
  const WorkspaceProjectHeader({
    required this.project,
    required this.collapsed,
    required this.onToggle,
    required this.onNewChat,
    required this.onMenu,
    super.key,
  });

  /// The project of the group.
  final Project project;

  /// Whether the chats of the group are hidden.
  final bool collapsed;

  /// Called when the title is pressed.
  final VoidCallback onToggle;

  /// Called when the new chat button is pressed.
  final VoidCallback onNewChat;

  /// Called when the ⋯ button is pressed, with its rect in global coordinates.
  final ValueChanged<Rect> onMenu;

  @override
  State<WorkspaceProjectHeader> createState() => _WorkspaceProjectHeaderState();
}

class _WorkspaceProjectHeaderState extends State<WorkspaceProjectHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localization = Localization.of(context);
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(color: colors.muted, fontSize: 11, fontWeight: FontWeight.w600);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: InkWell(
          onTap: widget.onToggle,
          hoverColor: colors.border.withValues(alpha: 0.5),
          child: SizedBox(
            height: 28,
            child: Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: Row(
                children: <Widget>[
                  Icon(
                    widget.collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 16,
                    color: colors.muted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  if (_hovered)
                    _HeaderButton(
                      tooltip: localization.newChat,
                      icon: Icons.add,
                      onPressed: widget.onNewChat,
                    ),
                  Builder(
                    builder: (buttonContext) => _HeaderButton(
                      tooltip: localization.projectActions,
                      icon: Icons.more_horiz,
                      onPressed: () {
                        final box = buttonContext.findRenderObject()! as RenderBox;
                        widget.onMenu(box.localToGlobal(Offset.zero) & box.size);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon),
    iconSize: 16,
    color: context.colors.muted,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 24, height: 24),
    visualDensity: VisualDensity.compact,
    onPressed: onPressed,
  );
}

/// {@template workspace_no_chats_hint}
/// The muted "no chats yet" line under a project without chats.
/// {@endtemplate}
class WorkspaceNoChatsHint extends StatelessWidget {
  /// {@macro workspace_no_chats_hint}
  const WorkspaceNoChatsHint({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 8, 4),
    child: Text(
      Localization.of(context).noChatsYet,
      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: context.colors.muted),
    ),
  );
}
