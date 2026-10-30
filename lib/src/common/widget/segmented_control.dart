import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';

/// {@template segmented_control}
/// A row of mutually exclusive options; the [selected] one is highlighted.
/// {@endtemplate}
class SegmentedControl<T> extends StatelessWidget {
  /// {@macro segmented_control}
  const SegmentedControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// Value and label of every option.
  final List<(T, String)> segments;

  /// Value of the highlighted option.
  final T selected;

  /// Called with the value of the option the user tapped.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context).textTheme.bodySmall!;
    final radius = BorderRadius.circular(AppRadius.medium);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: radius,
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (value, label) in segments)
              _Segment(
                label: label,
                selected: value == selected,
                style: theme,
                onTap: () => onChanged(value),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadius.small);
    return Semantics(
      button: true,
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colors.bg : Colors.transparent,
          borderRadius: radius,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                label,
                style: style.copyWith(
                  color: selected ? colors.text : colors.muted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
