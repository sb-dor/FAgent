import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/constant/window_constants.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:window_manager/window_manager.dart';

/// {@template app_title_bar}
/// The window's own title bar: [leading] controls, a [title] and [trailing] controls.
///
/// It leaves [kWindowButtonsInset] free at the left for the macOS window buttons, and the bar
/// drags the window (the [title] ignores pointers, so dragging it works too).
/// {@endtemplate}
class AppTitleBar extends StatelessWidget {
  /// {@macro app_title_bar}
  const AppTitleBar({
    required this.title,
    this.leading = const <Widget>[],
    this.trailing = const <Widget>[],
    super.key,
  });

  /// The centre of the bar, usually a [Text]; it is cut with an ellipsis when it does not fit.
  final Widget title;

  /// Controls before the [title].
  final List<Widget> leading;

  /// Controls after the [title].
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: colors.text, fontWeight: FontWeight.w600);
    // The drag area sits behind the controls: wrapping them would delay their taps while the
    // area waits to tell a tap from its double-tap.
    return SizedBox(
      height: kWindowTitleBarHeight,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DragToMoveArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
              ),
            ),
          ),
          Row(
            children: <Widget>[
              const SizedBox(width: kWindowButtonsInset),
              ...leading,
              const SizedBox(width: 8),
              Expanded(
                child: IgnorePointer(
                  child: DefaultTextStyle(
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ...trailing,
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
    );
  }
}

/// A 28 px icon button for the title bar.
class TitleBarButton extends StatelessWidget {
  /// Creates a title bar icon button; [tooltip] is required for accessibility.
  const TitleBarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    super.key,
  });

  /// Glyph of the button.
  final IconData icon;

  /// Hover hint and accessibility label.
  final String tooltip;

  /// Called on tap; `null` disables the button.
  final VoidCallback? onPressed;

  /// Color of the glyph; the muted one by default. A disabled button is always dimmed.
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(
      icon,
      size: 18,
      color: onPressed == null
          ? context.colors.muted.withValues(alpha: 0.4)
          : color ?? context.colors.muted,
    ),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
  );
}
