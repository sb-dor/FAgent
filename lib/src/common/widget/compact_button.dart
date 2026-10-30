import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';

/// {@template compact_button}
/// A small text button for cards inside the side panes: filled with the accent when [primary],
/// outlined otherwise. [icon] goes before the [label].
/// {@endtemplate}
class CompactButton extends StatelessWidget {
  /// {@macro compact_button}
  const CompactButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    super.key,
  });

  /// The text of the button.
  final String label;

  /// Called on tap; `null` disables the button.
  final VoidCallback? onPressed;

  /// Icon before the [label].
  final IconData? icon;

  /// Whether the button is the main action of its card.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textStyle = Theme.of(context).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w500);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small));
    const padding = EdgeInsets.symmetric(horizontal: 10);
    const minimumSize = Size(0, 28);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[Icon(icon, size: 14), const SizedBox(width: 4)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
    return primary
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: minimumSize,
              padding: padding,
              shape: shape,
              textStyle: textStyle,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: minimumSize,
              padding: padding,
              shape: shape,
              textStyle: textStyle,
              foregroundColor: colors.text,
              side: BorderSide(color: colors.border),
              backgroundColor: colors.bg,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: child,
          );
  }
}
