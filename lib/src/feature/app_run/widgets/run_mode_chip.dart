import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/selector_chip.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/build_mode.dart';

/// {@template run_mode_chip}
/// The build mode chip (debug, profile, release) of the next start, in the title bar and the Run
/// tab.
/// {@endtemplate}
class RunModeChip extends StatelessWidget {
  /// {@macro run_mode_chip}
  const RunModeChip({required this.mode, required this.onSelected, super.key});

  /// The chosen mode.
  final BuildMode mode;

  /// Called with the mode picked from the menu.
  final ValueChanged<BuildMode> onSelected;

  @override
  Widget build(BuildContext context) => SelectorChip<BuildMode>(
    label: mode.name,
    menuWidth: 160,
    sections: <AppMenuSection<BuildMode>>[
      AppMenuSection<BuildMode>(
        items: <AppMenuItem<BuildMode>>[
          for (final value in BuildMode.values)
            AppMenuItem<BuildMode>(value: value, title: value.name, selected: value == mode),
        ],
      ),
    ],
    onSelected: onSelected,
  );
}
