import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_page_scaffold.dart';

/// {@template workspace_settings_page}
/// The Settings screen. Sections are placeholders until the milestones that deliver them.
/// {@endtemplate}
class WorkspaceSettingsPage extends StatelessWidget {
  /// {@macro workspace_settings_page}
  const WorkspaceSettingsPage({super.key});

  /// Where each section comes from; the rest have no milestone yet and say "coming soon".
  static const Map<String, String> _milestones = <String, String>{
    'agents': 'M5',
    'mcp': 'M5',
    'flutter': 'M2',
  };

  @override
  Widget build(BuildContext context) {
    final data = WorkspaceConfigInhWidget.of(context).dataController;
    final localization = Localization.of(context);
    final sections = <(String id, IconData icon, String label)>[
      ('general', Icons.tune, localization.settingsGeneral),
      ('agents', Icons.smart_toy_outlined, localization.settingsAgents),
      ('mcp', Icons.hub_outlined, localization.settingsMcp),
      ('permissions', Icons.shield_outlined, localization.settingsPermissions),
      ('flutter', Icons.flutter_dash, localization.settingsFlutter),
      ('appearance', Icons.palette_outlined, localization.settingsAppearance),
      ('shortcuts', Icons.keyboard_outlined, localization.settingsShortcuts),
    ];
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final selected = sections.firstWhere(
          (section) => section.$1 == data.section,
          orElse: () => sections.first,
        );
        return WorkspacePageScaffold(
          title: localization.settings,
          sections: sections,
          selected: selected.$1,
          onSelect: (id) => data.openView(WorkspaceView.settings, section: id),
          child: SectionPlaceholder(
            icon: selected.$2,
            title: selected.$3,
            milestone: _milestones[selected.$1],
          ),
        );
      },
    );
  }
}
