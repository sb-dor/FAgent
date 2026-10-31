import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agents_config_widget.dart';
import 'package:flutter_code_agent/src/feature/agents/widgets/agents_settings_section.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/appearance_settings_section.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/general_settings_section.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/widgets/flutter_sdk_config_widget.dart';
import 'package:flutter_code_agent/src/feature/flutter_sdk/widgets/flutter_settings_section.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/mcp_servers_config_widget.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/mcp_settings_section.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/widgets/permission_rules_config_widget.dart';
import 'package:flutter_code_agent/src/feature/permission_rules/widgets/permissions_settings_section.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/controllers/workspace_data_controller.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/shortcuts_settings_section.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_config_widget.dart';
import 'package:flutter_code_agent/src/feature/workspace/widgets/workspace_page_scaffold.dart';

/// {@template workspace_settings_page}
/// The Settings screen: a rail or list of sections and the one that is open.
/// {@endtemplate}
class WorkspaceSettingsPage extends StatelessWidget {
  /// {@macro workspace_settings_page}
  const WorkspaceSettingsPage({super.key});

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
        final current = data.section;
        final selected = sections.any((section) => section.$1 == current)
            ? current!
            : sections.first.$1;
        return WorkspacePageScaffold(
          title: localization.settings,
          sections: sections,
          selected: selected,
          onSelect: (id) => data.openView(WorkspaceView.settings, section: id),
          subtitle: switch (selected) {
            'agents' => localization.settingsAgentsSubtitle,
            'mcp' => localization.settingsMcpSubtitle,
            'permissions' => localization.settingsPermissionsSubtitle,
            _ => null,
          },
          child: switch (selected) {
            'agents' => const AgentsConfigWidget(child: AgentsSettingsSection()),
            'mcp' => const McpServersConfigWidget(child: McpSettingsSection()),
            'permissions' => const PermissionRulesConfigWidget(child: PermissionsSettingsSection()),
            'appearance' => const AppearanceSettingsSection(),
            'shortcuts' => const ShortcutsSettingsSection(),
            'flutter' => const FlutterSdkConfigWidget(child: FlutterSettingsSection()),
            _ => const AgentsConfigWidget(child: GeneralSettingsSection()),
          },
        );
      },
    );
  }
}
