import 'package:flutter/widgets.dart';
import 'package:flutter_code_agent/project_creation/models/new_project_request.dart';
import 'package:flutter_code_agent/project_creation/widgets/option_chip.dart';

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
        OptionChip(
          key: ValueKey<String>('platform-${platform.name}'),
          label: _label(platform),
          selected: selected.contains(platform),
          onTap: () => onToggle(platform),
        ),
    ],
  );
}
