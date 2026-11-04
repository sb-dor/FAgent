import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/generated/generated_localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/feature/app_run/models/launch_config.dart';
import 'package:flutter_code_agent/src/feature/app_run/widgets/launch_config_texts.dart';

/// {@template run_split_button}
/// The Run button of the Run tab, split in two: the main part starts the app with the selected run
/// configuration, the arrow opens [menu] to choose another one.
///
/// While the app [running] the main part is Stop ([onStop]); the arrow still opens the menu, and a
/// choice counts from the next start.
///
/// The values of [menu] are configuration names, except [defaultValue] (Default) and
/// [launchJsonValue] (open or create `launch.json`); [onSelected] gets a name or `null` for
/// Default, and [onOpenLaunchJson] is called for the file. (A menu cannot report a `null` pick, so
/// Default has a value of its own.)
/// {@endtemplate}
class RunSplitButton extends StatefulWidget {
  /// {@macro run_split_button}
  const RunSplitButton({
    required this.label,
    required this.enabled,
    required this.onRun,
    required this.menu,
    required this.onSelected,
    required this.onOpenLaunchJson,
    this.disabledReason,
    this.menuTooltip,
    this.running = false,
    this.onStop,
    this.stopTooltip,
    this.onMenuOpening,
    super.key,
  });

  /// The value of the Default row of [menu].
  static const String defaultValue = '\u0000default';

  /// The value of the row that opens (or creates) `launch.json`.
  static const String launchJsonValue = '\u0000launch.json';

  /// What the main part says: `Run`, or `Run · <name>`. Long names are cut short; the tooltip has
  /// the whole text.
  final String label;

  /// Whether the main part can start the app.
  final bool enabled;

  /// Why the main part cannot start the app, for its tooltip; `null` shows [label].
  final String? disabledReason;

  /// Called when the main part is pressed and [enabled].
  final VoidCallback onRun;

  /// The rows of the menu the arrow opens.
  final List<AppMenuSection<String?>> menu;

  /// Called with the name of the configuration the user chose, `null` for Default.
  final ValueChanged<String?> onSelected;

  /// Called when the user chooses to open `launch.json` (or to create it).
  final VoidCallback onOpenLaunchJson;

  /// The hover hint of the arrow.
  final String? menuTooltip;

  /// Whether the app builds or runs: the main part is then Stop.
  final bool running;

  /// Called when Stop is pressed.
  final VoidCallback? onStop;

  /// The hover hint of Stop.
  final String? stopTooltip;

  /// Called, and waited for, before the menu opens; the owner reads `launch.json` again here and
  /// the menu shows the rows it then gives.
  final Future<void> Function()? onMenuOpening;

  @override
  State<RunSplitButton> createState() => _RunSplitButtonState();
}

class _RunSplitButtonState extends State<RunSplitButton> {
  static const double _height = 26;

  bool _opening = false;

  Future<void> _openMenu() async {
    if (_opening) return;
    _opening = true;
    try {
      await widget.onMenuOpening?.call();
      if (!mounted) return;
      // The owner rebuilds with the rows of the new read; wait for that frame to take them.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final box = context.findRenderObject()! as RenderBox;
      final picked = await showAppMenu<String?>(
        context: context,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        sections: widget.menu,
        width: 300,
      );
      switch (picked) {
        case null:
          break;
        case RunSplitButton.defaultValue:
          widget.onSelected(null);
        case RunSplitButton.launchJsonValue:
          widget.onOpenLaunchJson();
        case final name:
          widget.onSelected(name);
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.small);
    final filled = widget.enabled && !widget.running;
    final background = filled ? colors.accent : colors.bg;
    final foreground = widget.running
        ? colors.danger
        : filled
        ? colors.onAccent
        : colors.muted.withValues(alpha: 0.5);
    final arrowColor = filled ? colors.onAccent : colors.text;
    final divider = filled ? colors.onAccent.withValues(alpha: 0.35) : colors.border;
    final onPressed = widget.running
        ? widget.onStop
        : widget.enabled
        ? widget.onRun
        : null;
    final mainTooltip = widget.running
        ? widget.stopTooltip
        : widget.enabled
        ? widget.label
        : widget.disabledReason ?? widget.label;

    Widget main = InkWell(
      borderRadius: BorderRadius.horizontal(left: radius.topLeft),
      onTap: onPressed,
      child: SizedBox(
        height: _height,
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(widget.running ? Icons.stop : Icons.play_arrow, size: 16, color: foreground),
                if (!widget.running) ...<Widget>[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium!.copyWith(
                        color: foreground,
                        fontSize: 12,
                        height: 16 / 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (mainTooltip != null) main = Tooltip(message: mainTooltip, child: main);

    Widget arrow = InkWell(
      borderRadius: BorderRadius.horizontal(right: radius.topRight),
      onTap: _openMenu,
      child: SizedBox(
        height: _height,
        width: 24,
        child: Icon(Icons.arrow_drop_down, size: 18, color: arrowColor),
      ),
    );
    if (widget.menuTooltip != null) arrow = Tooltip(message: widget.menuTooltip, child: arrow);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(color: filled ? colors.accent : colors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(child: main),
            SizedBox(
              width: 1,
              height: _height,
              child: ColoredBox(color: divider),
            ),
            arrow,
          ],
        ),
      ),
    );
  }
}

/// The rows of the menu of [RunSplitButton]: Default, the configurations of [configs] (the one
/// named [selected] checked; one that cannot run is disabled with its reason as subtitle), and the
/// row for `launch.json` itself. A file that cannot be read is one disabled row in the place of the
/// configurations.
List<AppMenuSection<String?>> runConfigMenu({
  required GeneratedLocalization localization,
  required LaunchConfigs? configs,
  required String? selected,
}) {
  final read = configs is LaunchConfigsRead ? configs.configs : const <LaunchConfig>[];
  final seen = <String>{};
  return <AppMenuSection<String?>>[
    AppMenuSection<String?>(
      items: <AppMenuItem<String?>>[
        AppMenuItem<String?>(
          value: RunSplitButton.defaultValue,
          title: localization.runConfigDefault,
          selected: selected == null,
        ),
      ],
    ),
    if (configs is LaunchConfigsUnreadable)
      AppMenuSection<String?>(
        items: <AppMenuItem<String?>>[
          AppMenuItem<String?>(
            value: null,
            title: localization.launchUnreadableText(configs),
            icon: Icons.error_outline,
            enabled: false,
          ),
        ],
      ),
    if (read.isNotEmpty)
      AppMenuSection<String?>(
        items: <AppMenuItem<String?>>[
          for (final config in read)
            AppMenuItem<String?>(
              value: config.name,
              title: config.name,
              subtitle: switch (config) {
                LaunchConfig(:final unsupported?) => localization.launchUnsupportedText(
                  unsupported,
                ),
                LaunchConfig(hasPreLaunchTask: true) => localization.launchPreLaunchSkipped,
                _ => null,
              },
              // Of two configurations with the same name the first counts.
              selected: selected == config.name && seen.add(config.name),
              enabled: config.unsupported == null,
            ),
        ],
      ),
    if (configs != null)
      AppMenuSection<String?>(
        items: <AppMenuItem<String?>>[
          AppMenuItem<String?>(
            value: RunSplitButton.launchJsonValue,
            title: configs is LaunchConfigsMissing
                ? localization.runCreateLaunchJson
                : localization.runOpenLaunchJson,
            icon: configs is LaunchConfigsMissing ? Icons.add : Icons.description_outlined,
          ),
        ],
      ),
  ];
}
