import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';

/// {@template empty_state}
/// A centered placeholder: [icon], [title], an optional [message], an action button and a [badge].
/// {@endtemplate}
class EmptyState extends StatelessWidget {
  /// {@macro empty_state}
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.badge,
    super.key,
  });

  /// Illustration of the state.
  final IconData icon;

  /// Main line.
  final String title;

  /// Explanation under the [title].
  final String? message;

  /// Text of the action button; shown only together with [onAction].
  final String? actionLabel;

  /// Called when the action button is pressed.
  final VoidCallback? onAction;

  /// Optional badge above the [title], e.g. a `PreviewBadge`.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final message = this.message;
    final actionLabel = this.actionLabel;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 32, color: colors.muted),
              const SizedBox(height: 12),
              if (badge != null) ...<Widget>[badge!, const SizedBox(height: 8)],
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleSmall!.copyWith(color: colors.text),
              ),
              if (message != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium!.copyWith(color: colors.muted),
                ),
              ],
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
