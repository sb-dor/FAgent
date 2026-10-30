import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';

/// {@template workspace_sidebar_row}
/// A 28 px action row of the sidebar: [icon], [label], and a [shortcut] hint or a [trailing]
/// widget at the end.
///
/// Without [onTap] the row is drawn but does nothing.
/// {@endtemplate}
class WorkspaceSidebarRow extends StatelessWidget {
  /// {@macro workspace_sidebar_row}
  const WorkspaceSidebarRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcut,
    this.trailing,
    this.outlined = false,
    this.muted = false,
    super.key,
  });

  /// Leading icon.
  final IconData icon;

  /// Text of the row; ends with an ellipsis when it does not fit.
  final String label;

  /// Called when the row is pressed.
  final VoidCallback? onTap;

  /// Hint of the keyboard shortcut, e.g. `⌘N`.
  final String? shortcut;

  /// Widget at the end of the row, instead of [shortcut].
  final Widget? trailing;

  /// A white row with a border: the primary action.
  final bool outlined;

  /// Muted text and icon: a secondary action.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final color = muted ? colors.muted : colors.text;
    final shortcut = this.shortcut;
    final trailing = this.trailing;
    return Semantics(
      button: true,
      child: Material(
        color: outlined ? colors.bg : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          side: outlined ? BorderSide(color: colors.border) : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          hoverColor: colors.border.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium!.copyWith(color: color),
                  ),
                ),
                if (shortcut != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(shortcut, style: textTheme.bodySmall!.copyWith(color: colors.muted)),
                ],
                if (trailing != null) ...<Widget>[const SizedBox(width: 8), trailing],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
