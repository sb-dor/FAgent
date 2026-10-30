import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';

/// Emphasis of a [SelectorChip] or an [AppMenuItem].
enum AppTone {
  /// Regular look.
  neutral,

  /// Needs attention, e.g. Accept edits / Auto.
  warn,

  /// Dangerous, e.g. Bypass permissions.
  danger,
}

/// {@template selector_chip}
/// A 28 px pill (radius `AppRadius.medium`) that shows the current choice (agent, model, mode, …).
///
/// With [sections] it opens an [AppMenu] under (or above) itself on tap and
/// reports the picked value through [onSelected]; without them it is a plain
/// button that calls [onPressed].
/// {@endtemplate}
class SelectorChip<T> extends StatelessWidget {
  /// {@macro selector_chip}
  const SelectorChip({
    required this.label,
    this.icon,
    this.tone = AppTone.neutral,
    this.tooltip,
    this.sections,
    this.onSelected,
    this.onPressed,
    super.key,
  });

  /// Text of the chip.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Colors the chip: [AppTone.warn] and [AppTone.danger] use the soft/strong
  /// pairs of the palette.
  final AppTone tone;

  /// Hover hint.
  final String? tooltip;

  /// Menu sections. When `null`, empty or without any item the chip does not
  /// open a menu.
  final List<AppMenuSection<T>>? sections;

  /// Called with the value the user picked from the menu.
  final ValueChanged<T>? onSelected;

  /// Called on tap when there is no menu ([sections] is `null` or has no items).
  final VoidCallback? onPressed;

  Future<void> _open(BuildContext context, List<AppMenuSection<T>> sections) async {
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final picked = await showAppMenu<T>(context: context, anchor: anchor, sections: sections);
    if (picked != null) onSelected?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (tone) {
      AppTone.neutral => (colors.surface, colors.text),
      AppTone.warn => (colors.warnSoft, colors.warn),
      AppTone.danger => (colors.dangerSoft, colors.danger),
    };
    final menu = sections != null && sections!.any((section) => section.items.isNotEmpty)
        ? sections
        : null;
    final radius = BorderRadius.circular(AppRadius.medium);
    final textStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: foreground, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500);

    Widget chip = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: tone == AppTone.neutral ? Border.all(color: colors.border) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: menu != null ? () => _open(context, menu) : onPressed,
          child: SizedBox(
            height: 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 14, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: textStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (menu != null) ...<Widget>[
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, size: 16, color: foreground),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) chip = Tooltip(message: tooltip, child: chip);
    return chip;
  }
}
