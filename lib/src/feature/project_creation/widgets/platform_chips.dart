import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/feature/project_creation/models/new_project_request.dart';

/// {@template platform_chips}
/// One toggle chip for each [FlutterPlatform]; a chosen one has the accent background and a check.
/// {@endtemplate}
class PlatformChips extends StatelessWidget {
  /// {@macro platform_chips}
  const PlatformChips({required this.selected, required this.onToggle, super.key});

  /// The platforms that are on.
  final Set<FlutterPlatform> selected;

  /// Called with the platform whose chip was tapped.
  final ValueChanged<FlutterPlatform> onToggle;

  static String _label(FlutterPlatform platform) => switch (platform) {
    FlutterPlatform.ios => 'iOS',
    FlutterPlatform.android => 'Android',
    FlutterPlatform.macos => 'macOS',
    FlutterPlatform.web => 'Web',
    FlutterPlatform.windows => 'Windows',
    FlutterPlatform.linux => 'Linux',
  };

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: <Widget>[
      for (final platform in FlutterPlatform.values)
        _PlatformChip(
          key: ValueKey<String>('platform-${platform.name}'),
          label: _label(platform),
          selected: selected.contains(platform),
          onTap: () => onToggle(platform),
        ),
    ],
  );
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadius.small + 2);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.accentSoft : colors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? colors.accent : colors.border),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
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
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: selected ? colors.accent : colors.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
