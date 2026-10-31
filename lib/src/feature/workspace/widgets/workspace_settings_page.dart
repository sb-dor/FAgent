import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agents_config_widget.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agents_settings_section.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/appearance_settings_section.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/general_settings_section.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/mcp_servers_config_widget.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/mcp_settings_section.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/widgets/permission_rules_config_widget.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/widgets/permissions_settings_section.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/shortcuts_settings_section.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_page_scaffold.dart';

/// {@template workspace_settings_page}
/// The Settings screen. Sections that are not built yet are placeholders until the milestones that
/// deliver them.
/// {@endtemplate}
class WorkspaceSettingsPage extends StatelessWidget {
  /// {@macro workspace_settings_page}
  const WorkspaceSettingsPage({super.key});

  /// Where each section comes from; the rest have no milestone yet and say "coming soon".
  static const Map<String, String> _milestones = <String, String>{'flutter': 'M2'};

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
          subtitle: switch (selected.$1) {
            'agents' => localization.settingsAgentsSubtitle,
            'mcp' => localization.settingsMcpSubtitle,
            'permissions' => localization.settingsPermissionsSubtitle,
            _ => null,
          },
          child: switch (selected.$1) {
            'general' => const AgentsConfigWidget(child: GeneralSettingsSection()),
            'agents' => const AgentsConfigWidget(child: AgentsSettingsSection()),
            'mcp' => const McpServersConfigWidget(child: McpSettingsSection()),
            'permissions' => const PermissionRulesConfigWidget(child: PermissionsSettingsSection()),
            'appearance' => const AppearanceSettingsSection(),
            'shortcuts' => const ShortcutsSettingsSection(),
            _ => SectionPlaceholder(
              icon: selected.$2,
              title: selected.$3,
              milestone: _milestones[selected.$1],
            ),
          },
        );
      },
    );
  }
}
