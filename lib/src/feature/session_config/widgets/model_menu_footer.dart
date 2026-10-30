import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/segmented_control.dart';
import 'package:flutter_code_agent/src/feature/session_config/models/config_option.dart';

/// {@template model_menu_footer}
/// The bottom of the model menu: the effort as segments (when the agent has one) and
/// "make default for new chats".
/// {@endtemplate}
class ModelMenuFooter extends StatelessWidget {
  /// {@macro model_menu_footer}
  const ModelMenuFooter({
    required this.effort,
    required this.onEffort,
    required this.onMakeDefault,
    super.key,
  });

  /// The effort setting; `null` hides the segments.
  final SelectConfigOption? effort;

  /// An effort segment was tapped.
  final ValueChanged<String> onEffort;

  /// "Make default for new chats" was ticked.
  final VoidCallback onMakeDefault;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final effort = this.effort;
    final small = Theme.of(context).textTheme.bodySmall!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (effort != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  localization.effortLabel,
                  style: small.copyWith(
                    color: context.colors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                // Six segments are wider than the menu: shrink instead of overflowing.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SegmentedControl<String>(
                    segments: <(String, String)>[
                      for (final choice in effort.choices) (choice.value, choice.name),
                    ],
                    selected: effort.currentValue,
                    onChanged: onEffort,
                  ),
                ),
              ],
            ),
          ),
        CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          value: false,
          onChanged: (_) => onMakeDefault(),
          title: Text(
            localization.makeDefaultForNewChats,
            style: small.copyWith(color: context.colors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
