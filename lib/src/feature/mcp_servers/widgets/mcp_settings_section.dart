import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/settings_row.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/controller/mcp_servers_controller.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/mcp_server_row.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/mcp_servers_config_widget.dart';

/// {@template mcp_settings_section}
/// The "MCP servers" section of Settings: a card with a [McpServerRow] per server (the built-in
/// ones first), and the buttons that add a stdio or HTTP server or import a `.mcp.json`.
/// {@endtemplate}
class McpSettingsSection extends StatelessWidget {
  /// {@macro mcp_settings_section}
  const McpSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = McpServersConfigInhWidget.of(context);
    return ListenableBuilder(
      listenable: scope.servers,
      builder: (context, _) {
        final localization = Localization.of(context);
        final colors = context.colors;
        final state = scope.servers.state;
        final servers = switch (state) {
          McpServers$CompletedState(:final servers) ||
          McpServers$ErrorState(:final servers) => servers,
          McpServers$InitialState() => const <McpServer>[],
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (state is McpServers$InitialState) ...<Widget>[
              Text(
                localization.mcpLoading,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
              ),
              const SizedBox(height: 12),
            ],
            if (state is McpServers$ErrorState) ...<Widget>[
              _ServersError(onRetry: scope.servers.retry),
              const SizedBox(height: 12),
            ],
            if (servers.isNotEmpty) ...<Widget>[
              SettingsCard(
                children: <Widget>[
                  for (final server in servers)
                    McpServerRow(key: ValueKey<String>('mcp-row-${server.id}'), server: server),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  CompactButton(
                    label: localization.mcpAddStdio,
                    onPressed: () => scope.openAddDialog(McpTransport.stdio),
                  ),
                  CompactButton(
                    label: localization.mcpAddHttp,
                    onPressed: () => scope.openAddDialog(McpTransport.http),
                  ),
                  CompactButton(
                    label: localization.mcpImport,
                    icon: Icons.file_open_outlined,
                    onPressed: scope.importFromFile,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Says that the servers could not be listed, with a button to try again.
class _ServersError extends StatelessWidget {
  const _ServersError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          localization.mcpLoadFailed,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: context.colors.danger),
        ),
        CompactButton(label: localization.retry, onPressed: onRetry),
      ],
    );
  }
}
