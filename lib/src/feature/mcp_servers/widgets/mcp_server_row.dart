import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/design/app_text.dart';
import 'package:flutter_code_agent/src/common/design/app_theme.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';
import 'package:flutter_code_agent/src/common/widget/app_menu.dart';
import 'package:flutter_code_agent/src/common/widget/compact_button.dart';
import 'package:flutter_code_agent/src/common/widget/preview_badge.dart';
import 'package:flutter_code_agent/src/feature/app_settings/widgets/settings_row.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/models/mcp_server.dart';
import 'package:flutter_code_agent/src/feature/mcp_servers/widgets/mcp_servers_config_widget.dart';

/// {@template mcp_server_row}
/// One MCP server in the section: where it stands (a dot), its name, what it runs or where it
/// connects, what it offers, and the controls that fit it.
///
/// Every server can be turned off in single projects. One the user added also has a switch for
/// everything and can be removed; a built-in one has neither.
/// {@endtemplate}
class McpServerRow extends StatelessWidget {
  /// {@macro mcp_server_row}
  const McpServerRow({required this.server, super.key});

  /// The server to show.
  final McpServer server;

  /// What the server starts or connects to, in one line; `null` when it has neither.
  String? get _target => switch (server.transport) {
    McpTransport.stdio when server.command != null => <String>[
      server.command!,
      ...server.args,
    ].join(' '),
    McpTransport.http => server.url,
    McpTransport.stdio => null,
  };

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final scope = McpServersConfigInhWidget.of(context);
    final target = _target;
    final summary = server.summary;
    final toolCount = server.toolCount;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              server.name,
              style: textTheme.bodyMedium!.copyWith(
                color: colors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (server.builtin) _Tag(label: localization.mcpBuiltin),
            if (server.isPreview) const PreviewBadge(),
          ],
        ),
        if (target != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              target,
              style: AppText.mono(context, size: 12).copyWith(color: colors.muted),
            ),
          ),
        if (summary != null || toolCount != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                if (summary != null)
                  Text(summary, style: textTheme.bodySmall!.copyWith(color: colors.muted)),
                if (toolCount != null)
                  Text(
                    localization.mcpToolCount(toolCount),
                    style: textTheme.bodySmall!.copyWith(color: colors.muted),
                  ),
              ],
            ),
          ),
        if (server.status == McpStatus.needsAuth)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CompactButton(
              label: localization.mcpSignIn,
              onPressed: scope.showSignInComingSoon,
            ),
          ),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!server.builtin)
          Tooltip(
            message: localization.mcpEnabledSwitch,
            child: Switch(
              value: server.enabled,
              onChanged: (enabled) => scope.actions.setEnabled(server.id, enabled: enabled),
            ),
          ),
        _ProjectsButton(server: server),
        if (!server.builtin)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: localization.mcpRemove,
            color: colors.muted,
            onPressed: () => scope.confirmRemove(server),
            visualDensity: VisualDensity.compact,
            iconSize: 18,
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dot = Padding(
            padding: const EdgeInsets.only(top: 5, right: 10),
            child: _StatusDot(status: server.status),
          );
          if (constraints.maxWidth < SettingsRow.wrapWidth) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    dot,
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 4),
                controls,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              dot,
              Expanded(child: info),
              const SizedBox(width: 16),
              controls,
            ],
          );
        },
      ),
    );
  }
}

/// The dot before the name: green when the server is ready, amber when it needs a sign-in, grey
/// while nothing is known.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final McpStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (status) {
      McpStatus.ready => colors.ok,
      McpStatus.needsAuth => colors.warn,
      McpStatus.unknown => colors.muted,
    };
    return SizedBox.square(
      dimension: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// The small "built-in" pill after the name.
class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label,
          maxLines: 1,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: colors.muted, fontSize: 10, height: 14 / 10),
        ),
      ),
    );
  }
}

/// The button that opens the list of projects the server can be turned off in.
class _ProjectsButton extends StatelessWidget {
  const _ProjectsButton({required this.server});

  final McpServer server;

  Future<void> _open(BuildContext context) async {
    final scope = McpServersConfigInhWidget.of(context);
    final localization = Localization.of(context);
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    final projects = scope.projects;
    final picked = await showAppMenu<int>(
      context: context,
      anchor: anchor,
      width: 260,
      sections: <AppMenuSection<int>>[
        AppMenuSection<int>(
          title: localization.mcpProjectsMenuTitle,
          items: <AppMenuItem<int>>[
            for (final project in projects)
              AppMenuItem<int>(
                value: project.id,
                title: project.name,
                selected: !server.disabledIn.contains(project.id),
              ),
            if (projects.isEmpty)
              AppMenuItem<int>(value: -1, title: localization.mcpProjectsNone, enabled: false),
          ],
        ),
      ],
    );
    if (picked == null) return;
    scope.actions.setEnabled(
      server.id,
      enabled: server.disabledIn.contains(picked),
      projectId: picked,
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.folder_off_outlined),
    tooltip: Localization.of(context).mcpProjects,
    color: context.colors.muted,
    onPressed: () => _open(context),
    visualDensity: VisualDensity.compact,
    iconSize: 18,
  );
}
