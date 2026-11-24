import 'package:flutter/material.dart';
import 'package:flutter_code_agent/_core/design/app_colors.dart';
import 'package:flutter_code_agent/_core/design/app_theme.dart';

/// {@template option_chip}
/// A small chip of the New project form: a chosen one has the accent background and a check.
/// {@endtemplate}
class OptionChip extends StatelessWidget {
  /// {@macro option_chip}
  const OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.exclusive = false,
    this.enabled = true,
    super.key,
  });

  /// The text of the chip.
  final String label;

  /// Whether the option is on.
  final bool selected;

  /// Called when the chip is tapped.
  final VoidCallback onTap;

  /// Whether the chip is one of a group where only one is on (a radio), not a toggle.
  final bool exclusive;

  /// Whether the chip can be tapped; a disabled one is muted.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadius.small + 2);
    return Semantics(
      selected: exclusive ? null : selected,
      checked: exclusive ? selected : null,
      inMutuallyExclusiveGroup: exclusive,
      button: true,
      enabled: enabled,
      child: Material(
        color: selected ? colors.accentSoft : colors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? colors.accent : colors.border),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (selected) ...<Widget>[
                  Icon(Icons.check, size: 14, color: colors.accent),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: !enabled
                        ? colors.muted
                        : selected
                        ? colors.accent
                        : colors.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
